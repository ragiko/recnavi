require 'open-uri'
require 'nokogiri'
require 'erb'
require './conf/conf.rb'

# TODO: htmlの作成部分が汎用性ない
# TODO: 採用情報無い時, topのurlを返す
# TODO: 更新したときだけ通知とか

# spiderモジュール
class Recnavi 
  def initialize(id)
    @id = id
    @name = ""
    @domain = "https://job.rikunabi.com"
    @top_url = "https://job.rikunabi.com/2015/company/top/#{@id}/" 
    @top_doc = nil
    @seminar_doc = nil
  end

  def top_doc
    return @top_doc if @top_doc
    @top_doc = doc(@top_url)
  end

  def seminar_doc
    return @seminar_doc if @seminar_doc
    @seminar_doc = doc(event_link)
  end

  def doc(url)
    html = open(url) rescue nil
    Nokogiri::HTML(html) if !html.nil? rescue nil
  end

  def scrape
    corp = Corp.new(@id, name)

    return corp if !top_doc 
    return corp if warnning? or event_link == "" # topページに説明会が存在している
    return corp if !seminar_doc 

    body = seminar_doc.css("body").to_html

    # 企業のインスタンスを返す
    corp.event_link = event_link
    corp.event_html = body
    corp
  end

  # 企業名
  def name
    @name = top_doc.css(".rnhn_h2.gh_large.g_mb10.g_mt0").text if top_doc
    @name
  end

  # イベントが登録されていない警告の有無
  def warnning?
    return false if !top_doc 
    msg = top_doc.css(".g_clr_red.rnhn_p.g_txt_bold.g_mb2").text
    exist_msg = msg != ""
    exist_msg
  end

  # eventのリンクを返す
  def event_link
    return false if !top_doc 
    event_nodes = top_doc.css("#lnk_koshatubu_setevent")
    link = ""
    link = @domain + event_nodes[0][:href] if !event_nodes.empty?
    link
  end
end

# メールのヘルパー
# html作成のヘルパー
class MyMail
  # TODO: mailの設定を出来るようにする
  def self.options
    options = { :address              => "smtp.gmail.com",
                :port                 => 587,
                :domain               => "smtp.gmail.com",
                :user_name            => Conf::FROM_MAIL_ADDRESS,
                :password             => Conf::MAIL_PASSWORD,
                :authentication       => :plain,
                :enable_starttls_auto => true  } 
  end

  def self.make_html(name: "", link: "", body: "")
    corpname = "<h1>#{name}</h1>"
    if link == ""
      header = "<h2>採用情報はありませんでした</h2>"
    else
      header = "<h2><a href='#{link}'>URLはこっち</a></h2>"
    end
    [corpname, header, body].join("<br/>") + "<hr/><hr/>"
  end

  def self.template(body)
    t = <<-EOF
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <title></title>
    </head>
    <body>
        #{body}
    </body>
    </html>
    EOF
    t
  end
end

# 企業クラス
class Corp
  attr_accessor :id, 
                :name, 
                :event_link, 
                :event_html

  def initialize (
    id,
    name,
    event_link: "",
    event_html: "" )

    @id = id
    @name = name
    @event_link = event_link
    @event_html = event_html
  end
end

# 企業群クラス
require 'mail'

class Corps
  def initialize(ids)
    @ids = ids
    @corps = []
  end

  def run
    return @corps if @corps.size != 0
    for id in @ids
      @corps << Recnavi.new(id).scrape
    end
    @corps
  end

  def mail
    return false if run.size == 0

    html = make_html
    mail = Mail.new do
      from    Conf::FROM_MAIL_ADDRESS
      to      Conf::TO_MAIL_ADDRESS
      subject '企業説明会の情報'
      html_part do
        content_type 'text/html; charset=UTF-8'
        body html
      end
    end

    mail.delivery_method(:smtp, MyMail::options)
    mail.deliver!

    return true
  end

  def make_html
    return "" if run.size == 0

    contents = ""
    for corp in @corps
      #TODO: 会社名はどこか？
      #TODO: link body 無いときはイベント情報無し
      contents << MyMail::make_html(
        name: corp.name,
        link: corp.event_link, 
        body: corp.event_html)
    end
    MyMail::template(contents)
  end
end

if __FILE__ == $0
  require 'minitest/autorun'

  MiniTest.autorun
  class MyTest < MiniTest::Test
    def setup
      id = "r395400074"
      @recnavi = Recnavi.new(id)

      id = "r282300039"
      @recnavi_not_event = Recnavi.new(id)

      @corps = Corps.new([
        "r395400074", # タマノイ酢株式会社
        "r282300039", # カンロ株式会社
        "r659010039", # 日本ハムグループ
        "r727640069", # 株式会社サンヨーフーズ
        # 井村屋
        "r309300012", # 敷島製パン株式会社(pasco)
        "r717500005", # 日本製粉株式会社
        ###
        "r309200086", # 大石産業株式会社
        "r208310069", # アンダーツリー株式会社
        "r394130001", # テレコムサービス株式会社
        "r494361000"  # 株式会社glob
      ])
    end

    def teardown
    end

    def test_イベントあるときリンクはある
      assert !@recnavi.event_link.empty?
    end

    def test_イベントあるとき警告文はない
      assert_equal @recnavi.warnning?, false
    end

    def test_イベントあるとき情報があるか
      assert !@recnavi.scrape.event_html.empty?
    end

    def test_イベントないときリンクはない
      assert_equal @recnavi_not_event.event_link, ""
    end

    def test_イベントないとき警告文はある
      assert_equal @recnavi_not_event.warnning?, true
    end

    def test_イベントないとき情報取得できない
      assert_equal @recnavi_not_event.scrape.event_html, "" 
    end

    def test_recnavi_topから企業ネームを取得
      assert @recnavi.scrape.name != "" 
    end

    def test_corpus_htmlの作成
      assert @corps.make_html.size != 0
    end

    def test_corpus_htmlのmailが送信できるか
       assert_equal @corps.mail, true
    end
  end
end

