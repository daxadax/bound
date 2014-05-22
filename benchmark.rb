$: << 'lib'
require 'bound'
require 'ostruct'
require 'benchmark'

TestBoundary = Bound.required(:foo, :baz => Bound.required(:gonzo))

StructBoundary = Struct.new(:foo, :baz)
NestedStructBoundary = Struct.new(:gonzo)

def bench(key, &block)
  result = nil

  time = Benchmark.realtime { result = block.call }
  puts "Benchmarking '#{key}' --> #{time}ms"

  result
end

provider_objects = 10_000.times.map do |i|
  OpenStruct.new(
                 :foo => 'YES',
                 :baz => OpenStruct.new(:gonzo => 22)
                )
end

provider_hashes = 10_000.times.map do |i|
  {
   :foo => 'YES',
   :baz => {:gonzo => 22}
  }
end


bench '      bound w/ objt' do
  provider_objects.map do |provider|
    TestBoundary.new(provider)
  end
end

bench '      bound w/ hash' do
  provider_hashes.map do |provider|
    TestBoundary.new(provider)
  end
end

bench 'structbound w/ objt' do
  provider_objects.map do |provider|
    StructBoundary.new(
                       provider.foo,
                       NestedStructBoundary.new(provider.gonzo)
                      )
  end
end

bench 'structbound w/ hash' do
  provider_hashes.map do |provider|
    StructBoundary.new(
                       provider[:foo],
                       NestedStructBoundary.new(provider[:gonzo])
                      )
  end
end
