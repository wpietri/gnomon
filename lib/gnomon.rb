require "gnomon/version"

require 'open-uri'
require 'nokogiri'
require 'yaml'
require 'forwardable'

module Gnomon
  class Host
    def initialize(base_url, css: "a", id_pattern: %r{(.+)})
      @base_url = base_url
      @css = css
      @id_pattern = id_pattern
    end

    def name
      URI(@base_url.gsub(/\%+/,'')).host
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
    def self.load_all(directory)
      Dir.entries(directory).
          select { |f| f =~ /\.yaml$/ }.
          sort.
          map { |f| Gnomon::Scorecard.new("#{directory}/#{f}") }
    end

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

    def score(search_result)
      score = Score.new(@search)
      @top.each_with_index do |item, i|
        expected = i+1
        actual = search_result.position(item)
        score.add(item, expected, actual, weight(expected), [weight(actual), weight(expected)].min)
      end

      @more.each do |item|
        actual = search_result.position(item)
        points = actual.nil? ? 0 : MORE_WEIGHT
        score.add(item, nil, actual, MORE_WEIGHT, points)
      end

      search_result.each do |item|
        unless score.has(item)
          score.add(item, nil, search_result.position(item), 0, 0)
        end
      end
      score
    end

  end

  class Score
    extend Forwardable
    def_delegators :@entries, :size, :[], :each, :each_with_index

    attr :search
    def initialize(search)
      @entries = []
      @search = search
    end

    def add(item, expected_position, actual_position, expected_score, actual_score)
      @entries << ScoreEntry.new(item, expected_position, actual_position, expected_score, actual_score)
    end

    def has(item)
      @entries.map {|e| e.item}.include?(item)
    end

    def to_f
      expected = 0.0
      actual = 0.0
      @entries.each do |e|
        expected += e.expected_score
        actual += e.actual_score
      end
      actual/expected
    end

  end

  class ScoreEntry
    attr :item, :expected_position, :actual_position, :expected_score, :actual_score

    def initialize(item, expected_position, actual_position, expected_score, actual_score)
      @item = item
      @expected_position = expected_position
      @actual_position = actual_position
      @expected_score = expected_score
      @actual_score = actual_score
    end
  end

end