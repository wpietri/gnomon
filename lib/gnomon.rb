require "gnomon/version"

require 'open-uri'
require 'nokogiri'
require 'yaml'
require 'forwardable'
require 'benchmark'

module Gnomon
  class Host
    def initialize(base_url, css: "a", id_pattern: %r{(.+)})
      @base_url = base_url
      @css = css
      @id_pattern = id_pattern
    end

    def name
      URI(@base_url.gsub(/\%+/, '')).host
    end

    def search(search)
      url = search_url(search)
      found = nil
      timing = Benchmark.measure do
        found = get(url).css(@css)
      end
      result_ids = found
                       .map { |n| n['href'] }
                       .reject { |l| l.nil? }
                       .map { |l| l.match(@id_pattern) }
                       .reject { |m| m.nil? || m.size<1 }
                       .map { |m| m[1] }
      SearchResult.new(self, result_ids, timing)
    end

    def search_url(search)
      sprintf(@base_url, search)
    end

    def get(url)
      Nokogiri::HTML(open(url))
    end
  end

  class SearchResult
    include Enumerable

    attr :host

    def initialize(host, items, timing)
      @host = host
      @items = items
      @timing = timing
    end

    def each(&block)
      @items.each(&block)
    end

    def position(foo)
      pos = @items.find_index(foo)

      pos.nil? ? nil : pos + 1
    end

    def time
      @timing.real
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

    def score(result_a, result_b=nil)
      score = Score.new(@search, result_a, result_b)
      @top.each_with_index do |item, i|
        expected = i+1
        actual_a = result_a.position(item)
        actual_b = result_b ? result_b.position(item) : nil
        weight_ex = weight(expected)
        score.add(item, expected, actual_a, actual_b,
                  weight_ex, [weight(actual_a), weight_ex].min, [weight(actual_b), weight_ex].min)
      end

      @more.each do |item|
        actual_a = result_a.position(item)
        actual_b = result_b ? result_b.position(item) : nil
        points_a = actual_a.nil? ? 0 : MORE_WEIGHT
        points_b = actual_b.nil? ? 0 : MORE_WEIGHT
        score.add(item, nil, actual_a, actual_b, MORE_WEIGHT, points_a, points_b)
      end

      result_a.each do |item|
        unless score.has(item)
          actual_a = result_a.position(item)
          actual_b = result_b ? result_b.position(item) : nil
          score.add(item, nil, actual_a, actual_b, 0, 0, 0)
        end
      end
      if result_b
        result_b.each do |item|
          unless score.has(item)
            score.add(item, nil, nil, result_b.position(item), 0, 0, 0)
          end
        end
      end
      score
    end
  end

  class Score
    extend Forwardable
    def_delegators :@entries, :size, :[], :each, :each_with_index

    attr :search

    def initialize(search, result_a, result_b)
      @entries = []
      @search = search
      @result = result_a
      @result_b = result_b
    end

    def add(item, expected_position, actual_position_a, actual_position_b,
            expected_score, actual_score_a, actual_score_b)
      @entries << ScoreEntry.new(item, expected_position, actual_position_a, actual_position_b,
                                 expected_score, actual_score_a, actual_score_b)
    end

    def has(item)
      @entries.map { |e| e.item }.include?(item)
    end

    def host
      @result.host
    end

    def time
      @result.time
    end

    def dual
      !@result_b.nil?
    end

    #deprecated
    def to_f
      score_a
    end

    def score_a
      expected = 0.0
      actual = 0.0
      @entries.each do |e|
        expected += e.expected_score
        actual += e.actual_score
      end
      actual/expected
    end

    def score_b
      expected = 0.0
      actual = 0.0
      @entries.each do |e|
        expected += e.expected_score
        actual += e.actual_score_b
      end
      actual/expected
    end

  end

  class ScoreEntry
    attr :item, :expected_position, :actual_position, :actual_position_b,
         :expected_score, :actual_score, :actual_score_b

    def initialize(item, expected_position, actual_position_a, actual_position_b,
                   expected_score, actual_score_a, actual_score_b)
      @item = item
      @expected_position = expected_position
      @actual_position = actual_position_a
      @actual_position_b = actual_position_b
      @expected_score = expected_score
      @actual_score = actual_score_a
      @actual_score_b = actual_score_b
    end
  end

end