class IssuesController < ApplicationController
  def index
    @scope = Issue.internal.not_core.unlocked.humans.includes(:contributor).where("html_url <> ''")

    if params[:collab].present?
      @scope = @scope.collab(params[:collab])
    else
      @scope = @scope.all_collabs
    end

    apply_filters
    @collabs = @scope.unscope(where: :collabs).all_collabs.pluck(:collabs).flatten.inject(Hash.new(0)) { |h, e| h[e] += 1 ; h }
  end

  def collabs
    @scope = Issue.internal.not_core.unlocked.includes(:contributor).where("html_url <> ''")
    @collabs = Repository.external.pluck(:org).flatten.inject(Hash.new(0)) { |h, e| h[e] += 1 ; h }.sort_by{|k,v| -v }
  end

  def all
    @scope = Issue.internal.humans.unlocked.includes(:contributor).where("html_url <> ''")
    @scope = @scope.not_core if params[:exclude_core]

    apply_filters
  end

  def weekly
    @scope = Issue.internal.not_core.unlocked.where("html_url <> ''").includes(:contributor).all_collabs.not_draft.where('issues.closed_at > ? OR issues.created_at > ?', 1.week.ago, 1.week.ago)
    apply_filters
    @opened = @scope.where('issues.created_at > ?', 1.week.ago)
    @closed = @scope.where('issues.closed_at > ?', 1.week.ago)
    sort = params[:sort] || 'created_at'
    order = params[:order] || 'desc'

    @pagy, @issues = pagy(@scope.order(sort => order))
    @collabs = @scope.all_collabs.pluck(:collabs).flatten.inject(Hash.new(0)) { |h, e| h[e] += 1 ; h }.sort_by{|k,v| -v }
    @users = @scope.group(:user).count
  end

  def slow_response
    @date_range = 9
    @orginal_scope = Issue.internal.not_core.unlocked.where("html_url <> ''").not_draft.includes(:contributor)
    @scope = @orginal_scope.where('issues.created_at > ?', @date_range.days.ago).where('issues.created_at < ?', 2.days.ago)
    apply_filters

    @orginal_scope = @orginal_scope.where(repo_full_name: params[:repo_full_name]) if params[:repo_full_name].present?
    @orginal_scope = @orginal_scope.org(params[:org]) if params[:org].present?

    name = params[:repo_full_name] || params[:org] || 'All Internal Orgs'

    @response_times = [
      {
        name: name,
        data: @orginal_scope.where.not(response_time: nil).where('issues.created_at > ?', 1.year.ago).group_by_week('issues.created_at').average(:response_time).map do |k,v|
          if v
            [k,(v/60/60).round(1)]
          else
            [k,nil]
          end
        end
      }
    ]

    @slow = @scope.slow_response

    sort = params[:sort] || 'issues.created_at'
    order = params[:order] || 'desc'

    @pagy, @issues = pagy(@slow.order(sort => order))

    @collabs = @slow.all_collabs.pluck(:collabs).flatten.inject(Hash.new(0)) { |h, e| h[e] += 1 ; h }.sort_by{|k,v| -v }
    @users = @slow.group(:user).count
  end

  private

  def apply_filters
    @scope = @scope.exclude_user(params[:exclude_user]) if params[:exclude_user].present?
    @scope = @scope.exclude_repo(params[:exclude_repo]) if params[:exclude_repo].present?
    @scope = @scope.exclude_org(params[:exclude_org]) if params[:exclude_org].present?
    @scope = @scope.exclude_language(params[:exclude_language]) if params[:exclude_language].present?
    @scope = @scope.exclude_collab(params[:exclude_collab]) if params[:exclude_collab].present?

    @scope = @scope.where(comments_count: 0) if params[:uncommented].present?

    @scope = @scope.where('issues.created_at > ?', 1.month.ago) if params[:recent].present?

    @scope = @scope.no_milestone if params[:no_milestone].present?

    @scope = @scope.unlabelled if params[:unlabelled].present?

    @scope = @scope.where(user: params[:user]) if params[:user].present?
    @scope = @scope.where(state: params[:state]) if params[:state].present?
    @scope = @scope.where(repo_full_name: params[:repo_full_name]) if params[:repo_full_name].present?
    @scope = @scope.org(params[:org]) if params[:org].present?
    @scope = @scope.no_response if params[:no_response].present?

    @types = {
      'issues' => @scope.issues.count,
      'pull_requests' => @scope.pull_requests.count
    }

    @languages = Issue::LANGUAGES.to_h do |language|
      [language, @scope.language(language).count]
    end

    @scope = @scope.language(params[:language]) if params[:language].present?

    if params[:type].present?
      if params[:type] == 'issues'
        @scope = @scope.issues
      else
        @scope = @scope.pull_requests
      end
    end

    sort = params[:sort] || 'issues.created_at'
    order = params[:order] || 'desc'

    @pagy, @issues = pagy(@scope.order(sort => order))

    @users = @scope.group(:user).count
    @states = @scope.unscope(where: :state).group(:state).count
    @repos = @scope.unscope(where: :repo_full_name).group(:repo_full_name).count
    @orgs = @scope.unscope(where: :org).internal.group(:org).count
  end
end
