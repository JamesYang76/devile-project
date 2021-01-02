require "aws-sdk-ec2"

class AwsHelper
  class AwsHelperError < StandardError; end

  SYDNEY_AWS_REGION_NAME = "ap-southeast-2".freeze
  LINUX_USER = "deploy".freeze

  ##
  # This hash maps between Capistrano environment names and tags in AWS i.e.
  #
  #   "capistrano env name" => "AWS name tag(s) for that env"
  #
  # It allows this class to know what tag name(s) it should use to search for
  # EC2 instances that are in that particular Capistrano environment.
  #
  # instance names...
  CAP_ENV_TO_AWS_NAME_TAG_MAP = {
    "staging" => {
      "bastion" => ["StagingDevileProjectAutoscalingBastion"],
      "app_server" => ["StagingDevileProjectAutoscalingAppServer"]
    },
    # Todo
    # "production" => {
    # "bastion" => ["Todo"],
    #  "app_server" => ["Todo"]
    #}
  }.freeze

  def initialize(capistrano_env_name:,
                 aws_access_key_id:,
                 aws_secret_access_key:,
                 aws_region: SYDNEY_AWS_REGION_NAME,
                 logger: Logger.new($stdout))
    @logger = logger
    @aws_access_key_id = aws_access_key_id
    @aws_secret_access_key = aws_secret_access_key
    @aws_region = aws_region
    @env_name = capistrano_env_name

    @app_server_aws_name_tags = CAP_ENV_TO_AWS_NAME_TAG_MAP.fetch(@env_name).fetch("app_server")
    @bastion_aws_name_tags = CAP_ENV_TO_AWS_NAME_TAG_MAP.fetch(@env_name).fetch("bastion")
  end

  ##
  # Find an IP address of a bastion host in the given region. If there are
  # multiple bastion hosts, the IP address of the first one found is returned.
  #
  # @return [String] - IP Address of a bastion host
  #
  def bastion_host_ip_address # rubocop:disable Metrics/MethodLength
    ec2 = Aws::EC2::Client.new(
      region: @aws_region,
      access_key_id: @aws_access_key_id,
      secret_access_key: @aws_secret_access_key
    )

    resp = ec2.describe_instances(
      filters: [
        {
          name: "tag:Name",
          values: @bastion_aws_name_tags
        },
        {
          name: "instance-state-name",
          values: ["running"]
        }
      ]
    )

    ip_address = resp
                 .reservations
                 .map { |reservation| reservation.instances.map(&:public_ip_address) }
                 .flatten
                 .first

    log "In AWS regions '#{@aws_region}' for environment '#{@env_name}', I found bastion: #{ip_address}"

    ip_address
  rescue StandardError => e
    # Many things could go wrong here while digging into the expected responses from AWS
    log <<~EO_ERROR

      I failed to discover the IP address of the bastion host so I cannot
      complete the deployment.

      The error I found was: #{e.inspect}

      This is what I found when I looked for AWS credentials in the environment
      variables:
      Check that the values of the following environment variables are correct:

        DEPLOYMENT_AWS_ACCESS_KEY_ID
        DEPLOYMENT_AWS_SECRET_ACCESS_KEY

      If these are not correct then you should fix that. Otherwise this may have
      been caused by:

      * a network error
      * the server not running

      so you should check those too. Good luck!

    EO_ERROR
    raise AwsHelperError
  end

  ##
  # @return [String] - The name of the linux user on bastion servers
  #
  def bastion_linux_user
    LINUX_USER
  end

  ##
  # @return [String] - The name of the linux user on application servers
  #
  def app_server_linux_user
    LINUX_USER
  end

  ##
  # Used by Capistrano - see config/deploy/*.rb
  #
  def build_ssh_proxy_command
    "ssh -o StrictHostKeyChecking=no #{bastion_linux_user}@#{bastion_host_ip_address} -W %h:%p"
  rescue StandardError => e
    log <<~EO_ERROR

      I failed to setup Capistrano to deploy through a bastion host so I cannot continue.

      The error I found was: #{e.inspect}
    EO_ERROR
    raise AwsHelperError
  end

  ##
  # Find all EC2 instances in Sydney which have a 'Name' tag
  # indicating they are one of our Rails application servers
  #
  # @return [Array<String>] An array of hostnames e.g.
  #
  #   [
  #     "ip-10-3-46-182.ap-southeast-2.compute.internal",
  #     "ip-10-3-68-167.ap-southeast-2.compute.internal"
  #   ]
  #
  def vpc_internal_dns_names # rubocop:disable Metrics/MethodLength
    ec2 = Aws::EC2::Client.new(
      region: @aws_region,
      access_key_id: @aws_access_key_id,
      secret_access_key: @aws_secret_access_key
    )

    resp = ec2.describe_instances(
      filters: [
        {
          name: "tag:Name",
          values: @app_server_aws_name_tags
        },
        {
          name: "instance-state-name",
          values: ["running"]
        }
      ]
    )

    names = resp
            .reservations
            .map { |reservation| reservation.instances.map(&:private_dns_name) }
            .flatten

    log "In AWS regions '#{@aws_region}' I found the following app server(s): #{names.join(", ")}"

    names
  rescue StandardError => e
    # Many things could go wrong here while digging into the expected responses from AWS
    log <<~EO_ERROR

      I failed to discover the AWS internal DNS name of the server to deploy to so
      I cannot complete the deployment.

      The error I found was: #{e.inspect}

      This is what I found when I looked for AWS credentials in the environment
      variables:
      Check that the values of the following environment variables are correct:

        DEPLOYMENT_AWS_ACCESS_KEY_ID
        DEPLOYMENT_AWS_SECRET_ACCESS_KEY

      If these are not correct then you should fix that. Otherwise this may have
      been caused by:

      * a network error
      * the server not running

      so you should check those too. Good luck!

    EO_ERROR
    raise AwsHelperError
  end

  private

  def log(msg)
    @logger.info msg
  end
end
