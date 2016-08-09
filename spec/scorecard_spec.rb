require 'rspec'

result_items = %w{
        /dresses/its-an-inspired-taste-dress-in-bird
        /linens-aprons/hows-the-feather-out-there-tea-towel-set
        /totes-backpacks/on-your-last-leg-weekend-bag
        /shop/lighting/seen-in-a-new-flight-lamp
        /shop/wallets/call-wading-iphone-6-6s-case
        /stationery/pick-your-prompt-notebook-set
      }

describe Gnomon::Scorecard do
  card = Gnomon::Scorecard.new(File.dirname(__FILE__) + '/flamingo.yaml')

  it 'properly loads from a file' do
    expect(card.search).to eq('flamingo')
  end

  it 'gets 0 for no matches' do
    search_result = Gnomon::SearchResult.new([])
    expect(card.score(search_result)).to eq(0)
  end

  it 'gets 1 for full match' do
    search_result = Gnomon::SearchResult.new(result_items)
    expect(card.score(search_result)).to eq(1)
  end

  it 'gets high score for top matches' do
    search_result = Gnomon::SearchResult.new(result_items[0..2])
    expect(card.score(search_result)).to be_within(0.05).of(0.9)
  end
  it 'gets low score for lower matches' do
    search_result = Gnomon::SearchResult.new(result_items[3..6])
    expect(card.score(search_result)).to be_within(0.05).of(0.1)
  end

  it 'loads all the cards in a directory' do
    cards = Gnomon::Scorecard.load_all(File.dirname(__FILE__))
    expect(cards.length).to eq(1)
    expect(cards[0].search).to eq('flamingo')
  end
end