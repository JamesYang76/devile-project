set :rails_env, "staging"
set :branch, "master"

##
# We use the CAPISTRANO_DEPLOY_TO_LOCAL_DIR environment variable to signal to
# Capistrano that it should deploy to the same server it is run on. This covers
# the use-case where we run Capistrano after Chef to provision a server.
#
if ENV["CAPISTRANO_DEPLOY_TO_LOCAL_DIR"]
  server "localhost", roles: %w[app]
else
  aws_access_key_id = ENV.fetch("STAGING_DEPLOYMENT_AWS_ACCESS_KEY_ID")
  aws_secret_access_key = ENV.fetch("STAGING_DEPLOYMENT_AWS_SECRET_ACCESS_KEY")

  helper = AwsHelper.new(capistrano_env_name: "staging",
                         aws_access_key_id: aws_access_key_id,
                         aws_secret_access_key: aws_secret_access_key)
  set :ssh_options, {
    proxy: Net::SSH::Proxy::Command.new(helper.build_ssh_proxy_command),

    # We deploy to EC2 instances in an Autoscaling group so the actual
    # instances will change regularly enough that host key verification isn't
    # feasible.
    verify_host_key: false
  }
  role(:app, helper.vpc_internal_dns_names, user: helper.app_server_linux_user)
end
