require "gnomon/version"

require 'open-uri'
require 'nokogiri'
require 'yaml'

module Gnomon
  class Host
    def initialize(base_url, css: "a", id_pattern: %r{(.+)})
      @base_url = base_url
      @css = css
      @id_pattern = id_pattern
    end

    def search(search)
      url = sprintf(@base_url, search)
      found = get(url).css(@css)
      result_ids = found
                       .map { |n| n['href'] }
                       .reject { |l| l.nil? }
                       .map { |l| l.match(@id_pattern) }
                       .reject { |m| m.nil? || m.size<1 }
                       .map { |m| m[1] }
      SearchResult.new(result_ids)
    end

    def get(url)
      Nokogiri::HTML(open(url))
    end
  end

  class SearchResult
    include Enumerable

    def initialize(items)
      @items = items
    end

    def each(&block)
      @items.each(&block)
    end

    def position(foo)
      pos = @items.find_index(foo)

      pos.nil? ? nil : pos + 1
    end
  end

  TOP_WEIGHTS = 10.downto(1).map { |n| n*2 }
  MORE_WEIGHT = 1

  class Scorecard
    attr :search

    def initialize(path)
      raw_data = YAML.load_file(path)
      @search = raw_data['search']
      @top = raw_data['top']
      @more = raw_data['more']
    end

    def weight(position)
      return 0 if position.nil?
      if position <= 10
        TOP_WEIGHTS[position-1]
      else
        MORE_WEIGHT
      end
    end

    def score(result)
      total = 0.0
      base = 0.0
      @top.each_with_index do |item, i|
        expected = i+1
        actual = result.position(item)
        base += weight(expected)
        total += weight(actual)
      end

      @more.each do |item|
        actual = result.position(item)
        base += MORE_WEIGHT
        total += MORE_WEIGHT unless actual.nil?
      end
      total/base
    end

  end

end