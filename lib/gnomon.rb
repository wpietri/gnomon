require "gnomon/version"

require 'open-uri'
require 'nokogiri'
require 'yaml'
require 'forwardable'
require 'benchmark'
require 'markaby'


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
      begin
        source = open(url)
        Nokogiri::HTML(source)
      rescue Exception => e
        raise Exception.new("Failed to load URL %s : %s: %s" %
                                   [url, e.class, e.message])
      end
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

  TOP_WEIGHTS = Array.new(10,4)
  MORE_WEIGHT = 1

  class Scorecard
    def self.load_all(directory)
      result = Dir.entries(directory).
          select { |f| f =~ /\.yaml$/ }.
          sort.
          map { |f| Gnomon::Scorecard.new("#{directory}/#{f}") }
      raise "no scorecards found" unless result.length > 0
      result
    end

    attr :search

    def initialize(path)
      raw_data = YAML.load_file(path)
      @search = raw_data['search'].to_s.strip.gsub(/ /, '+')
      raise "invalid search for #{path}" unless search and search.length > 0
      @top = raw_data['top'] || []
      @more = raw_data['more'] || []
      raise "nothing to look for in #{path}" unless @top.length + @more.length > 0
    end

    def weight(position)
      return 0 if position.nil?
      if position <= TOP_WEIGHTS.length
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
      @result_a = result_a
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

    def host_a
      @result_a.host
    end

    def host_b
      @result_b.host
    end

    def time_a
      @result_a.time
    end

    def time_b
      @result_b.time
    end

    def dual
      !@result_b.nil?
    end

    #deprecated
    def to_f
      score_a
    end

    def score_a
      calc_score(@entries.map { |e| e.actual_score_a })
    end

    def score_b
      calc_score(@entries.map { |e| e.actual_score_b })
    end

    private
    def calc_score(actuals)
      expected = @entries.map { |e| e.expected_score }.reduce(0, :+)
      actual = actuals.reduce(0, :+)
      1.0 * actual / expected
    end

  end

  class ScoreEntry
    attr :item, :expected_position, :actual_position_a, :actual_position_b,
         :expected_score, :actual_score_a, :actual_score_b


    def initialize(item, expected_position, actual_position_a, actual_position_b,
                   expected_score, actual_score_a, actual_score_b)
      @item = item
      @expected_position = expected_position
      @actual_position_a = actual_position_a
      @actual_position_b = actual_position_b
      @expected_score = expected_score
      @actual_score_a = actual_score_a
      @actual_score_b = actual_score_b
    end
  end

  class ScorePage < Markaby::Builder
    def do_css
      %w(normalize skeleton site).each { |f| link rel: "stylesheet", href: "../css/#{f}.css"
      }
    end

    def expected_position_text(entry)
      if entry.expected_position
        entry.expected_position
      elsif entry.expected_score>0
        '*'
      else
        ''
      end
    end

    def standard_head(title)
      head do
        title title
        do_css
      end
    end

  end

  class ScoreReport
    def initialize(host_a, host_b, cards, scores)
      @host_a = host_a
      @host_b = host_b
      @cards = cards
      @scores = scores
      @report_time = Time.now.strftime("%d/%m/%Y %H:%M")
    end

    def do_css
      %w(normalize skeleton site).each { |f| link rel: "stylesheet", href: "../css/#{f}.css"
      }
    end

    def write_html_results(results_dir)
      @scores.each do |score|
        File.write("#{results_dir}/#{score.search}.html", score_as_html(score))
        puts "#{score.search} #{sprintf("%5.2f", score.to_f*100)}%"
      end
      File.write("#{results_dir}/index.html", index_for(@scores, @host_a, @host_b))
    end

    def index_for(scores, host_a, host_b)
      page = ScorePage.new
      title = page_title(host_a, host_b)
      page.html do
        standard_head(title)
        body do
          h1 title
          div class: 'index' do
            table do
              tr do
                if scores[0].dual
                  th 'score A'
                  th 'score B'
                  th 'search'
                  th 'time A'
                  th 'time B'
                else
                  th 'score'
                  th 'search'
                  th 'time'
                end
              end
              scores.each do |score|
                tr do
                  td sprintf("%.1f%%", score.score_a*100), class: 'score'
                  if score.dual
                    td sprintf("%.1f%%", score.score_b*100), class: 'score'
                  end
                  td { a score.search, href: "#{score.search}.html" }
                  td sprintf("%.1f s", score.time_a)
                  if score.dual
                    td sprintf("%.1f s", score.time_b)
                  end

                end
              end
            end
          end
        end
      end
      page.to_s
    end

    def page_title(host_a, host_b)
      "#{host_a.name} vs #{host_b.name} at #{@report_time}"
    end

    def score_as_html(score)
      page = ScorePage.new
      host = @host_b ? @host_b : @host_a
      title = page_title(@host_a, @host_b)
      page.html do
        standard_head(score.search)
        body do
          h1 title
          if score.dual
            h2 sprintf("#{score.search}: %.1f%% vs %.1f%%", score.score_a*100, score.score_b*100)
          else
            h2 sprintf("#{score.search}: %.1f%%", score.score_a*100)
          end
          div class: 'results' do
            table do
              tr do
                th(class: 'position') { span 'expected' }
                if score.dual
                  th(class: 'position') { span 'actual A' }
                  th(class: 'position') { span 'actual B' }
                  th(class: 'score') { span 'score A' }
                  th(class: 'score') { span 'score B' }
                else
                  th(class: 'position') { span 'actual' }
                  th(class: 'score') { span 'score' }
                end

                th(class: 'item') { span 'item' }
              end
              score.each do |entry|
                tr do
                  td expected_position_text(entry), class: 'position'
                  td entry.actual_position_a, class: 'position'
                  if score.dual
                    td entry.actual_position_b, class: 'position'
                  end
                  td entry.actual_score_a > 0 ? entry.actual_score_a : '', class: 'score'
                  if score.dual
                    td entry.actual_score_b > 0 ? entry.actual_score_b : '', class: 'score'
                  end
                  td(class: 'item') { a(entry.item, href: 'http://' + host.name + '/shop' + entry.item) }
                end
              end
            end
          end
        end
      end
      page.to_s
    end


  end


end