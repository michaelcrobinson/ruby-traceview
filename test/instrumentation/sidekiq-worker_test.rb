# Copyright (c) 2015 AppNeta, Inc.
# All rights reserved.

if RUBY_VERSION >= '2.0'
  require 'minitest_helper'
  require 'sidekiq'
  require_relative "../jobs/remote_call_worker_job"
  require_relative "../jobs/db_worker_job"
  require_relative "../jobs/error_worker_job"

  class SidekiqWorkerTest < Minitest::Test
    def setup
      clear_all_traces
      @collect_backtraces = TraceView::Config[:sidekiq][:collect_backtraces]
      @log_args = TraceView::Config[:sidekiq][:log_args]
    end

    def teardown
      TraceView::Config[:sidekiq][:collect_backtraces] = @collect_backtraces
      TraceView::Config[:sidekiq][:log_args] = @log_args
    end

    def test_reports_version_init
      init_kvs = ::TraceView::Util.build_init_report
      assert init_kvs.key?('Ruby.Sidekiq.Version')
      assert_equal "Sidekiq-#{::Sidekiq::VERSION}", init_kvs['Ruby.Sidekiq.Version']
    end

    def test_job_run
      # Queue up a job to be run
      jid = Sidekiq::Client.push('queue' => 'critical', 'class' => RemoteCallWorkerJob, 'args' => [1, 2, 3], 'retry' => false)

      # Allow the job to be run
      sleep 5

      traces = get_all_traces
      assert_equal 17, traces.count, "Trace count"
      validate_outer_layers(traces, "sidekiq-worker")
      valid_edges?(traces)

      # Validate entry layer KVs
      assert_equal 'always_sampled', traces[0]['TraceOrigin'],       "is always_sampled"
      assert_equal true,             traces[0].key?('SampleRate'),   "has SampleRate KV"
      assert_equal true,             traces[0].key?('SampleSource'), "has SampleSource KV"

      # Validate Webserver Spec KVs
      assert_equal Socket.gethostname,    traces[0]['HTTP-Host']
      assert_equal "Sidekiq_critical",    traces[0]['Controller']
      assert_equal "RemoteCallWorkerJob", traces[0]['Action']
      assert_equal "/sidekiq/critical/RemoteCallWorkerJob", traces[0]['URL']

      # Validate Job Spec KVs
      assert_equal "job",                 traces[0]['Spec']
      assert_equal "RemoteCallWorkerJob", traces[0]['JobName']
      assert_equal jid,                   traces[0]['JobID']
      assert_equal "critical",            traces[0]['Source']
      assert_equal "[1, 2, 3]",           traces[0]['Args']

      assert_equal false,                 traces[0].key?('Backtrace')
      assert_equal "net-http",            traces[4]['Layer']
      assert_equal "entry",               traces[4]['Label']
      assert_equal "memcache",            traces[15]['Layer']
    end

    def test_jobs_with_errors
      # Queue up a job to be run
      jid = Sidekiq::Client.push('queue' => 'critical', 'class' => ErrorWorkerJob, 'args' => [1, 2, 3], 'retry' => false)

      # Allow the job to be run
      sleep 5

      traces = get_all_traces
      assert_equal 3, traces.count, "Trace count"
      validate_outer_layers(traces, "sidekiq-worker")
      valid_edges?(traces)

      # Validate Webserver Spec KVs
      assert_equal Socket.gethostname, traces[0]['HTTP-Host']
      assert_equal "Sidekiq_critical", traces[0]['Controller']
      assert_equal "ErrorWorkerJob", traces[0]['Action']
      assert_equal "/sidekiq/critical/ErrorWorkerJob", traces[0]['URL']

      # Validate Job Spec KVs
      assert_equal "job", traces[0]['Spec']
      assert_equal "ErrorWorkerJob", traces[0]['JobName']
      assert_equal jid, traces[0]['JobID']
      assert_equal "critical", traces[0]['Source']
      assert_equal "[1, 2, 3]", traces[0]['Args']

      assert_equal traces[1]['Layer'], 'sidekiq-worker'
      assert_equal traces[1]['Label'], 'error'
      assert_equal traces[1]['ErrorClass'], "RuntimeError"
      assert traces[1].key?('ErrorMsg')
      assert traces[1].key?('Backtrace')
    end

    def test_collect_backtraces_default_value
      assert_equal TV::Config[:sidekiq][:collect_backtraces], false, "default backtrace collection"
    end

    def test_log_args_default_value
      assert_equal TV::Config[:sidekiq][:log_args], true, "log_args default "
    end
  end
end
