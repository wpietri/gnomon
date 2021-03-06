require 'rspec'

expected_items = %w{
        /dresses/its-an-inspired-taste-dress-in-bird
        /linens-aprons/hows-the-feather-out-there-tea-towel-set
        /totes-backpacks/on-your-last-leg-weekend-bag
        /shop/lighting/seen-in-a-new-flight-lamp
        /shop/wallets/call-wading-iphone-6-6s-case
        /stationery/pick-your-prompt-notebook-set
      }

def fake_result(items)
  Gnomon::SearchResult.new(Gnomon::Host.new("http://example.com/q=%s"), items, Benchmark.measure{})
end

describe Gnomon::Scorecard do
  card = Gnomon::Scorecard.new(File.dirname(__FILE__) + '/flamingo.yaml')

  it 'properly loads from a file' do
    expect(card.search).to eq('flamingo')
  end

  it 'has the search' do
    search_result = fake_result([])
    score = card.score(search_result)
    expect(score.search).to eq(card.search)
  end

  it 'has the host in the results' do
    search_result = fake_result([])
    score = card.score(search_result)
    expect(score.host.name).to eq('example.com')
  end

  it 'gets 0 for no matches' do
    search_result = fake_result([])
    expect(card.score(search_result).score_a).to eq(0)
  end

  it 'gets 1 for full match' do
    search_result = fake_result(expected_items)
    expect(card.score(search_result).score_a).to eq(1)
  end

  it 'gets high score for top matches' do
    search_result = fake_result(expected_items[0..2])
    expect(card.score(search_result).score_a).to be_within(0.05).of(0.9)
  end

  it 'gets low score for lower matches' do
    search_result = fake_result(expected_items[3..6])
    expect(card.score(search_result).score_a).to be_within(0.05).of(0.1)
  end

  it 'scores lower for bad order' do
    normal = fake_result(expected_items[0..2])
    flipped = fake_result(expected_items[0..2].reverse)
    expect(card.score(normal).score_a).to be > card.score(flipped).score_a
  end

  it 'has all the expected items' do
    search_result = fake_result(expected_items)
    score = card.score(search_result)
    pos = 0
    score.each do |entry|
      expect(entry.item).to eq(expected_items[pos])
      pos+=1
    end
  end

  it 'has any extra items' do
    search_result = fake_result(expected_items + ['/unexpected/item'])
    score = card.score(search_result)
    expect(score.size).to eq(expected_items.size + 1)
    expect(score[6].item).to eq('/unexpected/item')
    expect(score[6].expected_position).to be_nil
    expect(score[6].actual_position_a).to eq(7)
    expect(score[6].expected_score).to eq(0)
    expect(score[6].actual_score_a).to eq(0)
  end

  it 'has detail on each result' do
    search_result = fake_result(expected_items)
    score = card.score(search_result)
    expect(score[0].item).to eq('/dresses/its-an-inspired-taste-dress-in-bird')
    expect(score[0].expected_position).to eq(1)
    expect(score[0].actual_position_a).to eq(1)
    expect(score[0].expected_score).to eq(20)
    expect(score[0].actual_score_a).to eq(20)
  end

  it 'recognizes dual results' do
    single = card.score(fake_result(expected_items))
    dual = card.score(fake_result(expected_items), fake_result(expected_items.reverse))
    expect(single.dual).to be(false)
    expect(dual.dual).to be(true)
  end

  it 'has dual scores' do
    single = card.score(fake_result(expected_items))
    dual = card.score(fake_result(expected_items), fake_result(expected_items.reverse))
    expect(dual.score_a).to eq(single.score_a)
    expect(dual.score_b).to be < dual.score_a
  end

  it 'has details on a/b results when available' do
    score = card.score(fake_result(expected_items), fake_result(expected_items.reverse))
    expect(score[0].item).to eq('/dresses/its-an-inspired-taste-dress-in-bird')
    expect(score[0].actual_position_b).to eq(6)
    expect(score[0].actual_score_b).to eq(10)
  end

  it 'has a and b times' do
    dual = card.score(fake_result(expected_items), fake_result(expected_items.reverse))
    expect(dual.time_a).to be > 0
    expect(dual.time_b).to be > 0
  end

  it 'loads all the cards in a directory' do
    cards = Gnomon::Scorecard.load_all(File.dirname(__FILE__))
    expect(cards.length).to eq(1)
    expect(cards[0].search).to eq('flamingo')
  end
end