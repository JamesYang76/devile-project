require_relative "../lib/aws_helper"
require "dotenv/load"

# config valid for current version and patch releases of Capistrano
lock "~> 3.14"

set :application, "devile-project"
set :repo_url,    "git@github.com:JamesYang76/devile-project.git"

# Default branch is :master
# ask :branch, `git rev-parse --abbrev-ref HEAD`.chomp
set :user, "deploy"

# Default deploy_to directory is /var/www/my_app_name
set :deploy_to, "/home/#{fetch(:user)}/#{fetch(:application)}"

# Default value for :format is :airbrussh.
# set :format, :airbrussh

# You can configure the Airbrussh format using :format_options.
# These are the defaults.
# set :format_options, command_output: true, log_file: "log/capistrano.log", color: :auto, truncate: :auto

# Default value for :pty is false
# set :pty, true

# set :bundle_gemfile, -> { release_path.join("Gemfile") }
# set :bundle_config, {
#  deployment: true,
#  without: "development:test"
# }

# set :deploy_via, :remote_cache
# set :use_sudo, false
# set :normalize_asset_timestamps, false

#set :rails_env, "production"

# Default value for :linked_files is []
append :linked_files, ".env"

# Default value for linked_dirs is []
append :linked_dirs, "config/keys", "log", "tmp/pids", "tmp/cache", "tmp/sockets", "public/system"

# Default value for default_env is {}
set :default_env, path: "$HOME/.rbenv/shims:$HOME/bin:/snap/bin:$PATH"

set :rbenv_type, :system
set :rbenv_path, "/usr/lib/rbenv"
set :rbenv_ruby, File.read(".ruby-version").strip
set :rbenv_prefix, "RBENV_ROOT=#{fetch(:rbenv_path)} RBENV_VERSION=#{fetch(:rbenv_ruby)} /usr/bin/rbenv exec"
set :rbenv_map_bins, %w[rake gem bundle ruby rails]

set :assets_roles, [:app] # defaults to [:web]

# Default value for local_user is ENV['USER']
# set :local_user, -> { `git config user.name`.chomp }

# Default value for keep_releases is 5
# set :keep_releases, 5

namespace :deploy do
  desc "Restart application"
  task :restart do
    on roles(:app), in: :sequence, wait: 5 do
      execute :sudo, :systemctl, :restart, :puma
      #execute :sudo, :systemctl, :restart, :sidekiq
    end
  end

  task :start do
    on roles(:app) do
      execute :sudo, :systemctl, :start, :puma
    end
  end

  task :stop do
    on roles(:app) do
      execute :sudo, :systemctl, :stop, :puma
    end
  end

  after :publishing, :restart
end


namespace :dotenv do
  desc "Update .env file from AWS SecretsManager"
  task :update do
    on roles(:app) do
      # This script is on server at: ~deploy/bin/update-dotenv-file-from-secretsmanager
      execute "update-dotenv-file-from-secretsmanager"
    end
  end
end
