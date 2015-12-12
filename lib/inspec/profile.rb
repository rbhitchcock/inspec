# encoding: utf-8
# Copyright 2015 Dominik Richter. All rights reserved.
# author: Dominik Richter
# author: Christoph Hartmann

require 'inspec/metadata'
require 'pathname'

module Inspec
  class Profile # rubocop:disable Metrics/ClassLength
    def self.from_path(path, options = nil)
      opt = {}
      options.each { |k, v| opt[k.to_sym] = v } unless options.nil?
      opt[:path] = path
      Profile.new(opt)
    end

    attr_reader :params
    attr_reader :path

    def initialize(options = nil)
      @options = options || {}

      @params = {}
      @logger = options[:logger] || Logger.new(nil)

      @path = @options[:path]
      fail 'Cannot read an empty path.' if @path.nil? || @path.empty?
      fail "Cannot find directory #{@path}" unless File.directory?(@path)

      @params = read_metadata
      # use the id from parameter, name or fallback to nil
      @profile_id = options[:id] || params[:name] || nil

      @params[:rules] = rules = {}
      @runner = Runner.new(
        id: @profile_id,
        backend: :mock,
      )
      @runner.add_tests([@path])
      @runner.rules.each do |id, rule|
        file = rule.instance_variable_get(:@__file)
        rules[file] ||= {}
        rules[file][id] = {
          title: rule.title,
          desc: rule.desc,
          impact: rule.impact,
          checks: rule.instance_variable_get(:@checks),
          code: rule.instance_variable_get(:@__code),
          group_title: rule.instance_variable_get(:@__group_title),
        }
      end
    end

    def info
      res = @params.dup
      rules = {}
      res[:rules].each do |gid, group|
        next if gid.to_s.empty?
        path = gid.sub(File.join(@path, ''), '')
        rules[path] = { title: path, rules: {} }
        group.each do |id, rule|
          next if id.to_s.empty?
          data = rule.dup
          data.delete(:checks)
          data[:impact] ||= 0.5
          data[:impact] = 1.0 if data[:impact] > 1.0
          data[:impact] = 0.0 if data[:impact] < 0.0
          rules[path][:rules][id] = data
          # TODO: temporarily flatten the group down; replace this with
          # proper hierarchy later on
          rules[path][:title] = data[:group_title]
        end
      end
      res[:rules] = rules
      res
    end

    # Check if the profile is internall well-structured. The logger will be
    # used to print information on errors and warnings which are found.
    #
    # @return [Boolean] true if no errors were found, false otherwise
    def check # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      no_errors = true
      no_warnings = true
      warn = lambda { |msg|
        @logger.warn(msg)
        no_warnings = false
      }
      error = lambda { |msg|
        @logger.error(msg)
        no_warnings = no_errors = false
      }

      @logger.info "Checking profile in #{@path}"

      if @params[:name].to_s.empty?
        error.call('No profile name defined')
      elsif !(@params[:name].to_s =~ %r{^\S+\/\S+$})
        error.call('Profile name must be defined as: OWNER/ID')
      end

      warn.call('No version defined') if @params[:version].to_s.empty?
      warn.call('No title defined') if @params[:title].to_s.empty?
      warn.call('No maintainer defined') if @params[:maintainer].to_s.empty?
      warn.call('No supports defined') if @params[:supports].empty?
      @logger.info 'Metadata OK.' if no_warnings

      # check if deprecated metadata.rb exists
      warn.call('The use of `metadata.rb` is deprecated. Use `metadata.yml`.') if Pathname.new(path).join("metadata.rb").exist?

      # check if the profile is using the old test directory instead of the
      # new controls directory
      warn.call('Profile uses deprecated `test` directory, rename it to `controls`') if Pathname.new(path).join("test").exist? && !Pathname.new(path).join("controls").exist?

      no_warnings = true
      if @params[:rules].empty?
        warn.call('No rules were found.')
      end

      # iterate over hash of groups
      rules_counter = 0
      @params[:rules].each do |group, rules_array|
        @logger.debug "Verify all rules in  #{group}"
        rules_array.each do |id, rule|
          error.call('Avoid rules with empty IDs') if id.nil? or id.empty?
          warn.call("Rule #{id} has no title") if rule[:title].to_s.empty?
          warn.call("Rule #{id} has no description") if rule[:desc].to_s.empty?
          warn.call("Rule #{id} has impact > 1.0") if rule[:impact].to_f > 1.0
          warn.call("Rule #{id} has impact < 0.0") if rule[:impact].to_f < 0.0
          warn.call("Rule #{id} has no tests defined") if rule[:checks].nil? or rule[:checks].empty?
          rules_counter += 1
        end
      end
      @logger.debug "Found #{rules_counter} rules."

      @logger.info 'Rule definitions OK.' if no_warnings
      no_errors
    end

    private

    def read_metadata
      mpath = Pathname.new(path).join('metadata.yml')

      # fallback to metadata.rb if metadata.yml does not exist
      # TODO deprecated, will be removed in InSpec 1.0
      mpath = File.join(@path, 'metadata.rb') if !mpath.exist?
      Metadata.from_file(mpath, @profile_id, @logger)
    end
  end
end
