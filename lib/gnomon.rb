require "gnomon/version"

require 'open-uri'
require 'nokogiri'

module Gnomon
  class Host
    include Enumerable

    def initialize(base_url, css: "a", id_pattern: %r{(.+)})
      @base_url = base_url
      @css = css
      @id_pattern = id_pattern
    end

    def search(search)
      url = sprintf(@base_url, search)
      found = get(url).css(@css)
      Result.new(found
                     .map { |n| n['href'] }
                     .reject { |l| l.nil? }
                     .map { |l| l.match(@id_pattern) }
                     .reject { |m| m.nil? || m.size<1 }
                     .map { |m| m[1] })
    end

    def get(url)
      Nokogiri::HTML(open(url))
    end
  end

  class Result
    include Enumerable

    def initialize(items)
      @items = items
    end

    def each(&block)
      @items.each(&block)
    end
  end
end
