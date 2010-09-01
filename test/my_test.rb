require 'test_helper'

Encosion.options[:read_token] = 'pF-Nn_-cfM19El2Lr51QKZlsK3gfy20VnMF2EGt39e-wb3ABfu3jig..'
Encosion.options[:write_token] = ''

# do not commit any real tokens in this code
class MyTest < Test::Unit::TestCase
  def test_search_videos
    result = Encosion::Video.search_videos(:all => "topic:learned")
    assert_not_nil result
    assert_equal 2, result.count

    

  end
end
