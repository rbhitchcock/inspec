# encoding: utf-8
# author: Christoph Hartmann
# author: Dominik Richter

require 'resources/file'

# Usage:
# describe bond('bond0') do
#   it { should exist }
#   it { should have_interface 'eth0' }
# end

module Vulcano::Resources
  class Bond < File
    name 'bond'

    def initialize(bond)
      @bond = bond
      @path = "/proc/net/bonding/#{bond}"
      @content = nil
      @params = {}
      @loaded = false

      return skip_resource 'The `bond` resource is not supported on your OS yet.' if !vulcano.os.linux?
      @file = vulcano.file(@path)
    end

    # ensures the content is loaded before we return the params
    def params
      read_content if @loaded == false
      @params
    end

    def content
      read_content if @loaded == false
      @content
    end

    def exist?
      @file.exist?
    end

    def has_interface?(interface)
      params['Slave Interface'].include?(interface)
    end

    def interfaces
      params['Slave Interface']
    end

    def to_s
      "Bond #{@bond}"
    end

    private

    def read_content
      # parse the file
      @content = @file.content
      @params = SimpleConfig.new(
        @file.content,
        assignment_re: /^\s*([^:]*?)\s*:\s*(.*?)\s*$/,
        multiple_values: true,
      ).params if @file.exist?
      @loaded = true
      @content
    end
  end
end
