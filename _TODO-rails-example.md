# NVOI Rails Dashboard

A Rails app that serves as a dashboard for nvoi deploys running in CI.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         User's Repo                              │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐ │
│  │ deploy.enc   │  │ deploy.key   │  │ .github/workflows/     │ │
│  │ (committed)  │  │ (GH secret)  │  │   deploy.yml           │ │
│  └──────────────┘  └──────────────┘  └────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ git push
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    CI (GitHub Actions, etc.)                     │
│                                                                  │
│  gem install nvoi                                                │
│  echo "$DEPLOY_KEY" > deploy.key                                 │
│  nvoi deploy [--branch $BRANCH]                                  │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ nvoi gem:                                                   │ │
│  │   1. Decrypts deploy.enc with deploy.key                   │ │
│  │   2. Provisions infra / deploys app                        │ │
│  │   3. POSTs logs to callback_url (signed with deploy.key)   │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ HTTPS callbacks
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Rails Dashboard                              │
│                                                                  │
│  • Receives deploy logs via API                                  │
│  • Stores deploy history                                         │
│  • Real-time log streaming via Turbo                            │
│  • Config wizard (generates deploy.enc + CI files)              │
└─────────────────────────────────────────────────────────────────┘
```

**Key insight:** CI runs the deploy, Rails just watches.

---

## 1. App Setup

```bash
rails new nvoi-dashboard \
  --database=postgresql \
  --css=tailwind \
  --skip-jbuilder \
  --skip-action-mailbox \
  --skip-action-text

cd nvoi-dashboard
bundle add nvoi
bundle add omniauth-github
```

---

## 2. Database Schema

Simplified - no infra state tracking (CI handles that).

```ruby
# db/migrate/001_create_users.rb
class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.bigint :github_id, null: false, index: { unique: true }
      t.string :github_username, null: false
      t.text :github_access_token  # encrypted
      t.text :avatar_url
      t.timestamps
    end
  end
end

# db/migrate/002_create_projects.rb
class CreateProjects < ActiveRecord::Migration[8.0]
  def change
    create_table :projects do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :github_repo  # optional: user/repo
      t.binary :encrypted_config
      t.binary :encrypted_key
      t.string :callback_token, null: false, index: { unique: true }
      t.timestamps
    end
  end
end

# db/migrate/003_create_deploys.rb
class CreateDeploys < ActiveRecord::Migration[8.0]
  def change
    create_table :deploys do |t|
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.string :external_id, null: false  # CI run ID
      t.string :branch
      t.string :git_sha, limit: 40
      t.string :git_ref
      t.string :status, default: "running"
      t.string :ci_provider
      t.text :ci_run_url
      t.text :error_message
      t.jsonb :result_data  # tunnels, duration, etc.
      t.timestamp :started_at
      t.timestamp :finished_at
      t.timestamps
      t.index [:project_id, :external_id], unique: true
      t.index [:project_id, :created_at]
    end
  end
end

# db/migrate/004_create_deploy_logs.rb
class CreateDeployLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :deploy_logs do |t|
      t.references :deploy, null: false, foreign_key: { on_delete: :cascade }
      t.string :level, null: false
      t.text :message, null: false
      t.timestamp :logged_at, null: false
      t.index [:deploy_id, :logged_at]
    end
  end
end
```

---

## 3. Models

```ruby
# app/models/user.rb
class User < ApplicationRecord
  encrypts :github_access_token

  has_many :projects, dependent: :destroy
end

# app/models/project.rb
class Project < ApplicationRecord
  belongs_to :user
  has_many :deploys, dependent: :destroy

  encrypts :encrypted_config
  encrypts :encrypted_key

  before_create :generate_callback_token

  def callback_url
    Rails.application.routes.url_helpers.api_project_deploys_url(
      callback_token,
      host: Rails.application.config.app_host
    )
  end

  def deploy_key
    encrypted_key
  end

  def decrypted_config
    return {} unless encrypted_config && encrypted_key
    YAML.safe_load(
      Nvoi::Utils::Crypto.decrypt(encrypted_config, encrypted_key)
    )
  end

  def save_config(data)
    key = encrypted_key || SecureRandom.hex(32)
    self.encrypted_key = key
    self.encrypted_config = Nvoi::Utils::Crypto.encrypt(data.to_yaml, key)
    save!
  end

  private

  def generate_callback_token
    self.callback_token ||= SecureRandom.urlsafe_base64(32)
  end
end

# app/models/deploy.rb
class Deploy < ApplicationRecord
  belongs_to :project
  has_many :logs, class_name: "DeployLog", dependent: :delete_all

  enum :status, {
    running: "running",
    completed: "completed",
    failed: "failed"
  }

  scope :recent, -> { order(created_at: :desc).limit(50) }

  def duration
    return nil unless started_at && finished_at
    finished_at - started_at
  end

  def tunnels
    result_data&.dig("tunnels") || []
  end
end

# app/models/deploy_log.rb
class DeployLog < ApplicationRecord
  belongs_to :deploy

  after_create_commit :broadcast

  private

  def broadcast
    Turbo::StreamsChannel.broadcast_append_to(
      deploy,
      target: "deploy_logs",
      partial: "deploys/log_line",
      locals: { log: self }
    )
  end
end
```

---

## 4. API Controller (receives callbacks from gem)

```ruby
# app/controllers/api/deploys_controller.rb
module Api
  class DeploysController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :authenticate_user!
    before_action :set_project
    before_action :verify_signature

    # POST /api/projects/:callback_token/deploys/:external_id/logs
    def logs
      deploy = find_or_create_deploy

      params[:logs].each do |log_data|
        deploy.logs.create!(
          level: log_data[:level],
          message: log_data[:message],
          logged_at: log_data[:logged_at]
        )
      end

      head :ok
    end

    # POST /api/projects/:callback_token/deploys/:external_id/status
    def status
      deploy = find_or_create_deploy

      case params[:status]
      when "started"
        deploy.update!(
          status: :running,
          started_at: Time.current,
          git_sha: params[:git_sha],
          git_ref: params[:git_ref],
          branch: params[:git_ref],
          ci_provider: params[:ci_provider],
          ci_run_url: params[:ci_run_url]
        )
      when "completed"
        deploy.update!(
          status: :completed,
          finished_at: Time.current,
          result_data: {
            tunnels: params[:tunnels],
            duration_seconds: params[:duration_seconds]
          }
        )
        broadcast_status(deploy)
      when "failed"
        deploy.update!(
          status: :failed,
          finished_at: Time.current,
          error_message: params[:error]
        )
        broadcast_status(deploy)
      end

      head :ok
    end

    private

    def set_project
      @project = Project.find_by!(callback_token: params[:callback_token])
    end

    def verify_signature
      signature = request.headers["X-Nvoi-Signature"]
      expected = "sha256=" + OpenSSL::HMAC.hexdigest(
        "SHA256",
        @project.deploy_key,
        request.raw_post
      )

      head :unauthorized unless Rack::Utils.secure_compare(signature, expected)
    end

    def find_or_create_deploy
      @project.deploys.find_or_create_by!(external_id: params[:external_id])
    end

    def broadcast_status(deploy)
      Turbo::StreamsChannel.broadcast_replace_to(
        deploy,
        target: "deploy_status",
        partial: "deploys/status",
        locals: { deploy: deploy }
      )
    end
  end
end
```

---

## 5. Dashboard Controllers

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  before_action :authenticate_user!

  helper_method :current_user

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def authenticate_user!
    redirect_to login_path unless current_user
  end
end

# app/controllers/projects_controller.rb
class ProjectsController < ApplicationController
  before_action :set_project, only: [:show, :edit, :update, :destroy, :export]

  def index
    @projects = current_user.projects.order(updated_at: :desc)
  end

  def show
    @deploys = @project.deploys.recent
  end

  def new
    @project = current_user.projects.build
  end

  def create
    @project = current_user.projects.build(project_params)

    if @project.save
      redirect_to project_path(@project), notice: "Project created"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @config = @project.decrypted_config
  end

  def update
    @project.save_config(config_params.to_h)
    redirect_to project_path(@project), notice: "Config saved"
  rescue => e
    flash.now[:alert] = e.message
    render :edit, status: :unprocessable_entity
  end

  # Export deploy.enc, deploy.key, and CI workflow files
  def export
    send_data generate_export_zip,
              filename: "#{@project.name}-nvoi-config.zip",
              type: "application/zip"
  end

  private

  def set_project
    @project = current_user.projects.find(params[:id])
  end

  def project_params
    params.require(:project).permit(:name, :github_repo)
  end

  def config_params
    params.require(:config).permit!
  end

  def generate_export_zip
    require "zip"

    Zip::OutputStream.write_buffer do |zip|
      # deploy.enc
      zip.put_next_entry("deploy.enc")
      zip.write(@project.encrypted_config)

      # deploy.key (user adds to CI secrets)
      zip.put_next_entry("deploy.key.txt")
      zip.write("Add this as DEPLOY_KEY secret in your CI:\n\n")
      zip.write(@project.deploy_key)

      # GitHub Actions workflows
      zip.put_next_entry(".github/workflows/deploy-prod.yml")
      zip.write(generate_prod_workflow)

      zip.put_next_entry(".github/workflows/deploy-branch.yml")
      zip.write(generate_branch_workflow)

      # README
      zip.put_next_entry("NVOI_SETUP.md")
      zip.write(generate_readme)
    end.string
  end

  def generate_prod_workflow
    <<~YAML
      name: Deploy Production

      on:
        push:
          branches: [main]

      jobs:
        deploy:
          runs-on: ubuntu-latest
          steps:
            - uses: actions/checkout@v4

            - uses: ruby/setup-ruby@v1
              with:
                ruby-version: '3.3'

            - run: gem install nvoi

            - run: echo "${{ secrets.DEPLOY_KEY }}" > deploy.key

            - run: nvoi deploy
    YAML
  end

  def generate_branch_workflow
    <<~YAML
      name: Deploy Branch

      on:
        push:
          branches-ignore: [main]

      jobs:
        deploy:
          runs-on: ubuntu-latest
          steps:
            - uses: actions/checkout@v4

            - uses: ruby/setup-ruby@v1
              with:
                ruby-version: '3.3'

            - run: gem install nvoi

            - run: echo "${{ secrets.DEPLOY_KEY }}" > deploy.key

            - run: nvoi deploy --branch ${{ github.ref_name }}
    YAML
  end

  def generate_readme
    <<~MD
      # NVOI Setup

      ## Files in this export

      - `deploy.enc` - Encrypted deploy configuration (commit this)
      - `deploy.key.txt` - Encryption key (add as CI secret, DO NOT commit)
      - `.github/workflows/deploy-prod.yml` - Deploy on push to main
      - `.github/workflows/deploy-branch.yml` - Deploy branches with prefix

      ## Setup Steps

      1. Copy `deploy.enc` to your repo root
      2. Copy `.github/workflows/*.yml` to your repo
      3. Add `DEPLOY_KEY` secret in GitHub repo settings:
         - Go to Settings → Secrets and variables → Actions
         - Click "New repository secret"
         - Name: `DEPLOY_KEY`
         - Value: contents of `deploy.key.txt`
      4. Push to main to trigger first deploy

      ## How it works

      - Push to `main` → deploys to production
      - Push to any other branch → deploys with branch prefix (isolated infra)
      - Deploy logs stream to: #{@project.callback_url}
    MD
  end
end

# app/controllers/deploys_controller.rb
class DeploysController < ApplicationController
  before_action :set_project
  before_action :set_deploy, only: [:show]

  def index
    @deploys = @project.deploys.recent
  end

  def show
    @logs = @deploy.logs.order(:logged_at)
  end

  private

  def set_project
    @project = current_user.projects.find(params[:project_id])
  end

  def set_deploy
    @deploy = @project.deploys.find(params[:id])
  end
end
```

---

## 6. Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # Auth
  get "/auth/github/callback", to: "sessions#create"
  get "/login", to: "sessions#new"
  delete "/logout", to: "sessions#destroy"

  # API - receives callbacks from nvoi gem running in CI
  namespace :api do
    scope "/projects/:callback_token/deploys/:external_id" do
      post "logs", to: "deploys#logs"
      post "status", to: "deploys#status"
    end
  end

  # Dashboard
  resources :projects do
    member do
      get :export
    end

    resources :deploys, only: [:index, :show]
  end

  root "projects#index"
end
```

---

## 7. Views

```erb
<%# app/views/projects/show.html.erb %>
<div class="project">
  <header class="flex justify-between items-center">
    <h1><%= @project.name %></h1>
    <div class="actions">
      <%= link_to "Edit Config", edit_project_path(@project), class: "btn" %>
      <%= link_to "Export", export_project_path(@project), class: "btn btn-primary" %>
    </div>
  </header>

  <section class="callback-info">
    <h3>Callback URL</h3>
    <code><%= @project.callback_url %></code>
    <p class="text-sm text-gray-500">
      This is automatically included in your deploy.enc
    </p>
  </section>

  <section class="deploys">
    <h2>Recent Deploys</h2>

    <% if @deploys.any? %>
      <table>
        <thead>
          <tr>
            <th>Branch</th>
            <th>Commit</th>
            <th>Status</th>
            <th>Duration</th>
            <th>Started</th>
          </tr>
        </thead>
        <tbody>
          <% @deploys.each do |deploy| %>
            <tr>
              <td><%= deploy.branch %></td>
              <td>
                <code><%= deploy.git_sha&.first(7) %></code>
              </td>
              <td>
                <%= render "deploys/status_badge", deploy: deploy %>
              </td>
              <td>
                <% if deploy.duration %>
                  <%= pluralize(deploy.duration.round, "second") %>
                <% end %>
              </td>
              <td>
                <%= link_to time_ago_in_words(deploy.created_at) + " ago",
                            project_deploy_path(@project, deploy) %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    <% else %>
      <p class="empty">No deploys yet. Push to your repo to trigger a deploy.</p>
    <% end %>
  </section>
</div>

<%# app/views/deploys/show.html.erb %>
<div class="deploy">
  <header>
    <h1>Deploy <%= @deploy.git_sha&.first(7) %></h1>
    <div id="deploy_status">
      <%= render "deploys/status", deploy: @deploy %>
    </div>
  </header>

  <dl class="deploy-meta">
    <dt>Branch</dt>
    <dd><%= @deploy.branch %></dd>

    <dt>Commit</dt>
    <dd><code><%= @deploy.git_sha %></code></dd>

    <% if @deploy.ci_run_url %>
      <dt>CI Run</dt>
      <dd><%= link_to "View in #{@deploy.ci_provider}", @deploy.ci_run_url, target: "_blank" %></dd>
    <% end %>

    <% if @deploy.duration %>
      <dt>Duration</dt>
      <dd><%= pluralize(@deploy.duration.round, "second") %></dd>
    <% end %>

    <% @deploy.tunnels.each do |tunnel| %>
      <dt><%= tunnel["service_name"] %></dt>
      <dd><%= link_to tunnel["hostname"], "https://#{tunnel['hostname']}", target: "_blank" %></dd>
    <% end %>
  </dl>

  <%= turbo_stream_from @deploy %>

  <div id="deploy_logs" class="logs">
    <% @logs.each do |log| %>
      <%= render "deploys/log_line", log: log %>
    <% end %>
  </div>
</div>

<%# app/views/deploys/_log_line.html.erb %>
<div class="log-line log-<%= log.level %>">
  <span class="timestamp"><%= log.logged_at.strftime("%H:%M:%S.%L") %></span>
  <span class="level"><%= log.level %></span>
  <span class="message"><%= log.message %></span>
</div>

<%# app/views/deploys/_status.html.erb %>
<% case deploy.status.to_sym %>
<% when :running %>
  <span class="badge badge-blue animate-pulse">Deploying...</span>
<% when :completed %>
  <span class="badge badge-green">Completed</span>
<% when :failed %>
  <span class="badge badge-red">Failed</span>
  <% if deploy.error_message %>
    <p class="error-message"><%= deploy.error_message %></p>
  <% end %>
<% end %>

<%# app/views/deploys/_status_badge.html.erb %>
<% case deploy.status.to_sym %>
<% when :running %>
  <span class="badge badge-blue">●</span>
<% when :completed %>
  <span class="badge badge-green">✓</span>
<% when :failed %>
  <span class="badge badge-red">✗</span>
<% end %>
```

---

## 8. Config Editor (Optional Wizard)

```ruby
# app/controllers/configs_controller.rb
class ConfigsController < ApplicationController
  before_action :set_project

  def edit
    @config = @project.decrypted_config
    @step = params[:step]&.to_i || 1
  end

  def update
    # Merge step data into config
    current_config = @project.decrypted_config
    updated_config = current_config.deep_merge(config_params.to_h)

    @project.save_config(updated_config)

    if params[:next_step]
      redirect_to edit_project_config_path(@project, step: params[:next_step])
    else
      redirect_to project_path(@project), notice: "Config saved"
    end
  end

  private

  def set_project
    @project = current_user.projects.find(params[:project_id])
  end

  def config_params
    params.require(:config).permit!
  end
end
```

---

## Summary

This Rails app:

1. **Does NOT run deploys** - CI does that
2. **Receives callbacks** from nvoi gem running in CI
3. **Stores deploy history** and logs
4. **Streams logs in real-time** via Turbo
5. **Config wizard** generates deploy.enc
6. **Exports** deploy.enc + deploy.key + CI workflow files
7. **One secret** (DEPLOY_KEY) encrypts config AND signs callbacks

### User Flow

1. Create project in dashboard
2. Configure via wizard (or paste YAML)
3. Click "Export" → download zip
4. Commit `deploy.enc` to repo
5. Add `DEPLOY_KEY` to CI secrets
6. Push to trigger deploy
7. Watch logs stream in dashboard

### CI Files Generated

```yaml
# .github/workflows/deploy-prod.yml
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with: { ruby-version: '3.3' }
      - run: gem install nvoi
      - run: echo "${{ secrets.DEPLOY_KEY }}" > deploy.key
      - run: nvoi deploy

# .github/workflows/deploy-branch.yml
on:
  push:
    branches-ignore: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with: { ruby-version: '3.3' }
      - run: gem install nvoi
      - run: echo "${{ secrets.DEPLOY_KEY }}" > deploy.key
      - run: nvoi deploy --branch ${{ github.ref_name }}
```

Works with any CI that can run Ruby and has secrets support.
