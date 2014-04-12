require 'uri'
require 'net/http'
require 'open-uri'

class HackerNews

  VERSION = '0.2.1'

  # Returns the version string for the library.
  def self.version
    VERSION
  end

  BASE_URL           = "https://news.ycombinator.com"
  ITEM_URL           = "#{BASE_URL}/item?id=%s"
  USER_URL           = "#{BASE_URL}/user?id=%s"
  SAVED_URL          = "#{BASE_URL}/saved?id=%s"
  LOGIN_SUBMIT_URL   = "#{BASE_URL}/y"
  COMMENT_SUBMIT_URL = "#{BASE_URL}/r"

  class LoginError < RuntimeError; end

  # Creates a new HackerNews object.
  # If username and password are provided, login is called.
  def initialize(username=nil, password=nil)
    login(username, password) if username and password
  end

  # Log into Hacker News with the specified username and password.
  def login(username, password)
    response = post(LOGIN_SUBMIT_URL, 'fnid' => fnid, 'u' => username, 'p' => password)
    @username = username
    @password = password
    unless @cookie = response.header['set-cookie']
      raise LoginError, "Login credentials did not work."
    end
  end

  # Retrieves the karma for the logged in user, or for the specified username (if given).
  def karma(username=nil)
    user_page(username).match(/<td valign=top>karma\:<\/td><td>(\d+)<\/td>/)[1]
  end

  # Retrieves the average karma per post for the logged in user (must be logged in).
  def average_karma
    require_login!
    user_page.match(/<td valign=top>avg:<\/td><td>([\d\.]+)<\/td>/)[1]
  end

  # Retrieve the user's saved stories
  def saved
    require_login!

    @saved ||= get(SAVED_URL % @username).force_encoding("UTF-8")
    parse_stories @saved
  end

  # Retrieves the user page html for the specified username (or the current logged in user if none is specified).
  def user_page(username=nil)
    username ||= @username
    @user_pages ||= {}
    @user_pages[username] ||= begin
      get(USER_URL % username)
    end
  end

  # Up-vote a post or a comment by passing in the id number.
  def vote(id)
    require_login!
    url = get(ITEM_URL % id).match(/<a id=up_\d+ onclick="return vote\(this\)" href="(vote\?[^"]+)">/)[1]
    get(BASE_URL + '/' + url)
  end

  # Post a comment on a posted item or on another comment.
  def comment(id, text)
    require_login!
    fnid = get(ITEM_URL % id).match(/<input type=hidden name="fnid" value="([^"]+)"/)[1]
    post(COMMENT_SUBMIT_URL, 'fnid' => fnid, 'text' => text)
  end

  # Parse the comment tree for a story.
  # I used regex so as to not impose library requirements on a library that
  # is not my own.
  #
  # Returns an array of hashes.
  # E.G for ret-val. [{:id=>1, :poster=>:chasing_sparks, :text=>'.', :children=>[]}]
  def parse_story_comments(id)
    source = get(BASE_URL + "/item?id=#{id}")

    # The following regexp will break
    indentation  = '<img src="http:\/\/ycombinator.com\/images\/s.gif" height=1 width=(\d+)><\/td>'
    score        = '<span id=score_([0-9]+)>([0-9]+) point'
    user_id      = '<a href="user\\?id=([^"]+)">'
    time_ago     = '<\/a>([^\|]+)\|'
    comment_body = '<span class=\\"comment\\"><font color=#000000>(.*?)<\\/font>'
    regexp_str  = "#{indentation}.*?#{score}.*?#{user_id}.*?#{time_ago}.*?#{comment_body}"

    comment_regexp = Regexp.new(regexp_str, Regexp::MULTILINE)
    comments = source.scan(comment_regexp)

    commenter_stack = []
    comments.collect! do |comment|
      comment_hash = {
        :indentation => comment[0].to_i,
        :id          => comment[1],
        :points      => comment[2],
        :user_id     => comment[3],
        :post_date   => comment[4].lstrip.rstrip,:text=>comment[5],
        :children    => []
      }

      commenter_stack.pop until commenter_stack.empty? || commenter_stack.last[:indentation] < comment_hash[:indentation]
      commenter_stack.last[:children].push(comment_hash) if commenter_stack.length > 0
      commenter_stack.push(comment_hash)

      (commenter_stack.size == 1) ? comment_hash : nil
    end

    comments.compact
  end

  def parse_stories source
    story_regexp = Regexp.new("<td class=\"title\"><a href=\"(.*?)\"( rel=\"nofollow\")?>(.*?)</a>(.*?)?<span class=\"comhead\">", Regexp::MULTILINE)
    stories = source.scan(story_regexp)
    stories_stack = []
    stories.collect! do |story|
      story_hash = {
        :url   => story[0],
        :title => story[2]
      }
      stories_stack.push(story_hash)
    end
    stories_stack
  end

  def cookie
    @cookie
  end

  private

    def fnid
      form_html = get(BASE_URL + '/' + login_url)
      fnid_match = form_html.match(/<input type=hidden name="fnid" value="([^"]+)"/)
      raise CommsError unless fnid_match
      fnid_match[1]
    end

    def login_url
      login_match = get(BASE_URL).match(/href="([^"]+)">login<\/a>/)
      raise CommsError unless login_match
      login_match[1]
    end

    def url_path_and_query(url)
      if url.path and url.query
        "#{url.path}?#{url.query}"
      elsif not url.path.to_s.empty?
        url.path
      else
        '/'
      end
    end

    def get(url)
      url = URI.parse(url)
      response = Net::HTTP.start(url.host, url.port, use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_NONE) do |http|
        http.get(url_path_and_query(url), build_header)
      end
      response.body
    end

    def post(url, data)
      url = URI.parse(url)

      req = Net::HTTP::Post.new(url.path, build_header)
      req.set_form_data(data)

      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      http.request req
    end

    def build_header
      @cookie ? {'Cookie' => @cookie} : {}
    end

    def require_login!
      raise(LoginError, "You must log in to perform this action.") unless @cookie
    end

end
