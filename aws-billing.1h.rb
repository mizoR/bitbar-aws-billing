#!/usr/bin/env ruby
# frozen_string_literal: true

# <bitbar.title>AWS Billing</bitbar.title>
# <bitbar.version>v0.0.1</bitbar.version>
# <bitbar.author>mizoR</bitbar.author>
# <bitbar.author.github>mizoR</bitbar.author.github>
# <bitbar.image>https://user-images.githubusercontent.com/1257116/35317418-16b54094-011a-11e8-9580-f40ed65156f5.png</bitbar.image>
# <bitbar.dependencies>ruby,awscli</bitbar.dependencies>

require 'date'
require 'json'
require 'shellwords'

module BitBar
  module AwsBilling
    class MetricStatistics
      def initialize(start_time:, end_time:, period:, metric:, cloudwatch:)
        @start_time = start_time
        @end_time   = end_time
        @period     = period
        @metric     = metric
        @cloudwatch = cloudwatch
        @statistics = {}
      end

      def sum
        if @statistics.key?(:sum)
          return @statistics.fetch(:sum)
        end

        @statistics[:sum] = get_sum
      end

      private

      def get_sum
        params = build_params.merge(statistics: 'Sum')

        statistics = @cloudwatch.get_metric_statistics(params)

        if statistics.size > 0
          statistics.fetch(0).fetch('Sum')
        end
      end

      def build_params
        {
          namespace:   @metric['Namespace'],
          metric_name: @metric['MetricName'],
          dimensions:  @metric['Dimensions'],
          start_time:  @start_time,
          end_time:    @end_time,
          period:      @period,
        }
      end
    end

    class Metric
      def initialize(metric:, cloudwatch:)
        @metric     = metric
        @cloudwatch = cloudwatch
      end

      def service_name
        find_value_from_dementions_by(name: 'ServiceName')
      end

      def [](name)
        @metric[name]
      end

      def build_statistics(start_time:, end_time:, period:)
        MetricStatistics.new(
          start_time: start_time,
          end_time:   end_time,
          period:     period,
          metric:     self,
          cloudwatch: @cloudwatch,
        )
      end

      private

      def find_value_from_dementions_by(name:)
        @metric['Dimensions'].find { |d| d['Name'] == name }&.fetch('Value')
      end
    end

    class CloudWatch
      def initialize(region:)
        @region = region
      end

      def list_metrics(namespace:, metric_name:, dimensions:)
        dimensions = normalize_dimensions(dimensions)

        command =  %w|aws cloudwatch list-metrics|.tap { |builder|
          builder << '--namespace'   << namespace
          builder << '--metric-name' << metric_name
          builder << '--dimensions'  << dimensions
          builder << '--region'      << @region
        }

        metrics = run(command).fetch('Metrics')

        metrics.map { |m| Metric.new(metric: m, cloudwatch: self) }
      end

      def get_metric_statistics(namespace:, metric_name:, dimensions:, statistics:, start_time:, end_time:, period:)
        dimensions = normalize_dimensions(dimensions)

        command = %w|aws cloudwatch get-metric-statistics|.tap { |builder|
          builder << '--namespace'   << namespace
          builder << '--metric-name' << metric_name
          builder << '--start-time'  << start_time
          builder << '--end-time'    << end_time
          builder << '--period'      << period
          builder << '--statistics'  << statistics
          builder << '--dimensions'  << dimensions
          builder << '--region'      << @region
        }

        run(command).fetch('Datapoints')
      end

      private

      def run(command)
        if command.is_a?(Array)
          command = command.map { |c| Shellwords.escape(c) }.join(' ')
        end

        source = open("| #{command}") { |io| io.read }

        JSON.parse(source)
      end

      def normalize_dimensions(dimensions)
        if dimensions.is_a?(Hash) || dimensions.is_a?(Array)
          dimensions.to_json
        else
          dimensions
        end
      end
    end

    class App
      def initialize(icon:)
        @icon = icon
      end

      def run
        now        = Time.now.utc
        start_time = Time.utc(now.year, now.month)
        end_time   = Time.utc(now.year, now.month, now.day, now.hour, now.min)
        period     = (end_time - start_time).to_i

        metrics = cloudwatch.list_metrics(
          namespace:    'AWS/Billing',
          dimensions:   [ { Name: 'Currency', Value: 'USD' } ],
          metric_name: 'EstimatedCharges',
        )

        sums = metrics.each_with_object({}) do |metric, hash|
          service_name = metric.service_name || 'Total'

          statistics = metric.build_statistics(
            start_time: start_time.to_datetime,
            end_time:   end_time.to_datetime,
            period:     period,
          )

          if statistics.sum
            hash[service_name] = statistics.sum
          end
        end

        render(start_time: start_time, end_time: end_time, sums: sums)
      end

      private

      def render(start_time:, end_time:, sums:)
        puts <<-VIEW.gsub(/^ */, '')
          $#{sums['Total']} | image=#{@icon}
          ---
          #{start_time.to_date} ~ #{end_time.to_date} | color=grey font=Menlo-Bold
          #{sums.map { |name, sum| "#{name.ljust(18)} $#{sum} | color=grey font=Menlo" }.join("\n") }
          ---
          Open Bills | href=https://console.aws.amazon.com/billing/home?#/bills font=Menlo
        VIEW
      end

      def cloudwatch
        @cloudwatch ||= BitBar::AwsBilling::CloudWatch.new(region: 'us-east-1')
      end
    end
  end
end

if __FILE__ == $0
  ENV['PATH'] = "/usr/local/bin:#{ENV['PATH']}"

  require 'yaml'

  config = YAML.load(DATA.read).each_with_object({}) { |(k, v), h| h[k.to_sym] = v }

  BitBar::AwsBilling::App.new(config).run
end

__END__
icon: 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
