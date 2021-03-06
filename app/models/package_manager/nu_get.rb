# frozen_string_literal: true

module PackageManager
  class NuGet < Base
    HAS_VERSIONS = true
    HAS_DEPENDENCIES = true
    BIBLIOTHECARY_SUPPORT = true
    URL = "https://www.nuget.org"
    COLOR = "#178600"

    def self.package_link(package, version = nil)
      "https://www.nuget.org/packages/#{package.name}/#{version}"
    end

    def self.download_url(name, version = nil)
      "https://www.nuget.org/api/v2/package/#{name}/#{version}"
    end

    def self.install_instructions(package, version = nil)
      "Install-Package #{package.name}" + (version ? " -Version #{version}" : "")
    end

    def self.load_names(limit = nil)
      endpoints = name_endpoints
      segment_count = limit || endpoints.length - 1

      endpoints.reverse[0..segment_count].each do |endpoint|
        package_ids = get_names(endpoint)
        package_ids.each { |id| REDIS.sadd "nuget-names", id }
      end
    end

    def self.recent_names
      name_endpoints.reverse[0..2].map { |url| get_names(url) }.flatten.uniq
    end

    def self.name_endpoints
      get("https://api.nuget.org/v3/catalog0/index.json")["items"].map { |i| i["@id"] }
    end

    def self.get_names(endpoint)
      get(endpoint)["items"].map { |i| i["nuget:id"] }
    end

    def self.package_names
      REDIS.smembers "nuget-names"
    end

    def self.package(name)
      h = {
        name: name,
      }
      h[:releases] = get_releases(name)
      h[:versions] = versions(h, name)
      return {} unless h[:versions].any?

      h
    end

    def self.get_releases(name)
      latest_version = get_json("https://api.nuget.org/v3/registration5-semver1/#{name.downcase}/index.json")
      if latest_version["items"][0]["items"]
        releases = []
        latest_version["items"].each do |items|
          releases << items["items"]
        end
        releases.flatten!
      elsif releases.nil?
        releases = []
        latest_version["items"].each do |page|
          json = get_json(page["@id"])
          releases << json["items"]
        end
        releases.flatten!
      end
      releases
    rescue StandardError
      []
    end

    def self.mapping(package)
      item = package[:releases].last["catalogEntry"]

      {
        name: package[:name],
        description: description(item),
        homepage: item["packageUrl"],
        keywords_array: Array(item["tags"]),
        repository_url: repo_fallback("", item["packageUrl"]),
        releases: package[:releases],
        licenses: item["licenseExpression"],
      }
    end

    def self.description(item)
      item["description"].blank? ? item["summary"] : item["description"]
    end

    def self.versions(package, _name)
      package[:releases].map do |item|
        {
          number: item["catalogEntry"]["version"],
          published_at: item["catalogEntry"]["published"],
        }
      end
    end

    def self.dependencies(_name, version, mapped_package)
      current_version = mapped_package[:releases].find { |v| v["catalogEntry"]["version"] == version }
      dep_groups = current_version.fetch("catalogEntry", {})["dependencyGroups"] || []

      deps = dep_groups.map do |dep_group|
        next unless dep_group["dependencies"]

        dep_group["dependencies"].map do |dependency|
          {
            name: dependency["id"],
            requirements: parse_requirements(dependency["range"]),
          }
        end
      end.flatten.compact

      deps.map do |dep|
        {
          package_name: dep[:name],
          requirements: dep[:requirements],
          kind: "runtime",
          optional: false,
          platform: name.demodulize,
        }
      end
    end

    def self.parse_requirements(range)
      return unless range.present?

      parts = range[1..-2].split(",")
      requirements = []
      low_bound = range[0]
      high_bound = range[-1]
      low_number = parts[0].strip
      high_number = parts[1].try(:strip)

      # lowest
      low_sign = low_bound == "[" ? ">=" : ">"
      high_sign = high_bound == "]" ? "<=" : "<"

      # highest
      if high_number != low_number
        requirements << "#{low_sign} #{low_number}" if low_number.present?
        requirements << "#{high_sign} #{high_number}" if high_number.present?
      elsif high_number == low_number
        requirements << "= #{high_number}"
      elsif low_number.present?
        requirements << "#{low_sign} #{low_number}"
      end
      requirements << ">= 0" if requirements.empty?
      requirements.join(" ")
    end
  end
end
