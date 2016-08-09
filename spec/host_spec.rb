require 'rspec'

class FakeHost < Gnomon::Host
  attr :requested_url, :file_to_load

  def get(search)
    @requested_url = search
    @file_to_load = "spec/example-tops.html"
    Nokogiri::HTML(open(@file_to_load))
  end
end

describe Gnomon::Host do
  host = FakeHost.new("http://example.com/?q=%s", css: "div.product-info > p > a", id_pattern: %r{^/shop(.+)})

  it 'fetches the right url' do
    host.search('fnord')
    expect(host.requested_url).to eq("http://example.com/?q=fnord")
  end

  it 'finds the right stuff' do
    result = host.search('fnord')
    expect(result.count).to eq(50)
    expect(result.first).to eq('/blouses/trusty-travel-top-in-birds')
  end

  it 'will say where something is' do
    result = host.search('fnord')
    expect(result.position('/blouses/trusty-travel-top-in-birds')).to eq(1)
    expect(result.position('/blouses/does-not-eist')).to eq(nil)
  end
end