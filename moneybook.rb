#!/usr/bin/ruby
# $Id: moneybook.rb 100 2009-06-10 04:18:09Z taruisi $
$rev = "$Rev: 100 $".gsub("\$","").gsub(" ","")

# ログファイル名。スクリプト本体+logディレクトリ配下に作成する。
LOG_FILE_DIR  = File.dirname( File.expand_path(__FILE__) )+'/log/'
LOG_FILE_NAME = 'moneybook.log'
CONFIG_FILE   = File.dirname( File.expand_path(__FILE__) )+'/config.yml'

FLOAT_FORMAT   = "%.2f"
INTEGER_FORMAT = "%d"

# スクリプトの文字コードは UTF-8
$KCODE='u'

$VType = {
  0 => :Float,
  1 => :Integer,
  2 => :String,
  3 => :Time,
}
$VTypeR = $VType.invert
# 適宜変更したいところ。
SALT = "Elmo"

def log_write( str, always=nil, fname=LOG_FILE_NAME )
  name = LOG_FILE_DIR+fname
  if File.exist?( LOG_FILE_DIR ) && ( always || $Config[ 'DEBUG' ]) then
    open( name, 'a' ) do |f|
      f.puts( str )
    end
  end
end

# 一般ライブラリ。
require 'rubygems'
require 'digest/md5'
require 'kconv' 
require 'yaml'

unless File.exist?(CONFIG_FILE) then
  log_write( "Config file not exist", true )
  exit 0
end

$Config = YAML.load( open(CONFIG_FILE) )

# 設定しておくべき変数のチェック。以下の配列にある文字列は、$Configのキーとして値を保持していなければならない。
[ "SHORT_ITEM_FORMAT",
  "DB_NAME",
  "DB_USER",
  "SENDER",
  "LOG_TIME_FORMAT",
  "SMTP_SERVER",
  "SHORT_DATE_FORMAT",
  "TITLE",
  "DB_PASSWORD",
  "TARGET",
  "NORMAL_ITEM_SUMMARY_FORMAT",
  "NORMAL_ITEM_FORMAT" 
].each do |i|
  unless $Config.has_key?(i) then
    log_write( "Config Error No #{i}.", true )
    exit 0
  end
end

# ライブラリパスに、スクリプト本体のパスを追加する。
$: << File.dirname( File.expand_path(__FILE__) )

# 固有ライブラリ。
require 'mailprototype'
require 'maillib'
require 'dblib'

# 各項目の集計を行い、その結果を文字列で通知する関数。
# 入力は、ユーザオブジェクトと、集計開始を示すキーワード(Symbol)
def summarize( user, t1, t2 )
  ret = ''
  uret = ''
  sum = 0
  # 全ての項目の配列を求める。
  secs = Section.collect_all( user )
  # 項目名の最大長を求める。
  sec_width = 4
  secs.each { |s| sec_width=Kconv.toeuc(s.name).size if Kconv.toeuc(s.name).size>sec_width }
  # 項目毎の合計値を求める。集計開始は、指定されたキーワードに応じる。
  secs.each do |s|
    next if $VType[s.vtype]==:String
    if s.sum then
      # 項目毎の合計値は、SQLで集計してしまう。
      p = Item.summation( user, s, t1 )
      # 合計値が集計されなければ、空文字を通知。
      # 現状は、アイテムがなければ、０を通知するので、このコードは動作しない。
      return "" unless p
      # 集計行を表示する。文字幅は、予め計算していた最大長。
      ret += ($Config['NORMAL_ITEM_SUMMARY_FORMAT']+"\n")%([Kconv.toutf8(Kconv.toeuc(s.name).center(sec_width)), p.to_i, s.unit ])
      sum += p
    else
      ri = Item.find_recent( user, s )
      if ri then
        upd = ''
        upd = ri.updated_at.strftime('@%m/%d') if ri.updated_at < Item.time_period( t2 )
        uret += ($Config['NORMAL_ITEM_FORMAT']+"\n")%([Kconv.toutf8(Kconv.toeuc(s.name).center(sec_width)), (($VType[s.vtype]==:Integer)?(INTEGER_FORMAT):(FLOAT_FORMAT))%ri.price, s.unit, upd ])
      end
    end
  end
  # 合計値を加える。項目文字列長さに応じて表示位置を調整する。
  ret += " "*sec_width+"合計: %6d円" % sum
  ret = uret.chomp+"\n\n"+ret unless uret==''

  # 次にここ一週間の項目を列挙する。
  sd = ""
  Item.enumeration( user, t2 ).each do |i|
    ret += "\n\n" if sd==""
    lsd = i.updated_at.strftime( $Config[ 'SHORT_DATE_FORMAT' ] )
    unless sd==lsd then
      ret += "\n"+lsd+"\n"
      sd = lsd
    end
    if $VType[i.section.vtype]==:String then
      if /BLOG/=~i.section.name then
        ret += " "*4+i.comment+"\n"
#      else
#        if i.comment then
#          ret += 
#        end
      end
    else
      v = (($VType[i.section.vtype]==:Integer)?(INTEGER_FORMAT):(FLOAT_FORMAT))%i.price
      ret += (Kconv.toutf8($Config[ 'SHORT_ITEM_FORMAT' ]+"\n")) % [ Kconv.toutf8(Kconv.toeuc(i.section.name).center(sec_width)), v.to_s, i.section.unit ]
      ret += " "*4+i.comment+"\n" if i.comment
    end
  end
  ret
end

# メールで指定されたメールアドレスからユーザオブジェクトを求める。
found_user = User.check_maddr( mail.from.to_s )

# メールのフェーズを確認する。
mt = get_mail_type( found_user )

# メールフェーズ毎に処理を振り分ける。
case( mt[0] )

  # フェーズ１。
  #-- 1 → メールアドレス申請。メールアドレスが登録されていなければ、tokenメールを送る。
  #　　　　登録されていれば、雛型＆Instructionを送る
  # From : mailaddr
  # Body : none
  when :Phase_1
    if found_user then
      # ユーザがすでに登録されていれば、雛形メールを送る。
      reply_mail(
        $Config[ 'TITLE' ]+" "+$rev,
        make_mail_body( :Phase_2, [ maddr_token( found_user ) ] )
      )
    else
      # ユーザが登録されていなければ、要返信と記した、
      # token付きのメールを送る。ここではまだメールアドレスは登録しない。
      reply_mail(
        "[要返信]%s" % $Config[ 'TITLE' ]+" "+$rev,
        make_mail_body( :Phase_1, [ maddr_token( found_user ) ] )
      )
    end
  # フェーズ２。
  # -- 2 → メールアドレス登録。雛型＆Instructionを送る
  # From : mailaddr
  # Body :
  # [token]
  when :Phase_2
    # ユーザが登録されていなければ、ここでようやく登録する。
    unless found_user then
      usr = User.create( mail.from.to_s )
    end
    # その後、雛形メールを送付する。
    reply_mail( 
      $Config[ 'TITLE' ]+" "+$rev,
      make_mail_body( :Phase_2, [maddr_token( found_user )] )
    )
  
  # フェーズ３。
  # -- 3 → 金額登録。項目名がなければ、それも登録。Updateした雛型を送る。
  # From : mailaddr
  # [項目名] 金額
  # [token]
  #  * '項目名' という項目名は許さない。
  #  * 有効でないものがあったら、しらんぷり
  when :Phase_3
    Item.set_items( found_user, mt[1], mail.date )
    reply_mail(
      $Config[ 'TITLE' ]+" "+$rev,
      make_mail_body( :Phase_3,
                      [
                        Kconv.tojis( summarize( found_user, :this_month, [:seven_days, :this_month] ) ),
                        maddr_token( found_user )
                      ]
      )
    )

  # 削除指示。
  # DBにユーザを指定して実行するのみ。
  when :Destroy_Newest
    di = Item.delete_newest( found_user )
    if di then
      reply_mail( 
        $Config[ 'TITLE' ]+" "+$rev,
        make_mail_body( :Delete_newest,
                        [ Kconv.tojis(di[0]), di[1],
                          Kconv.tojis( summarize( found_user, :this_month, [:seven_days, :this_month] ) ),
                          maddr_token( found_user )
                        ]
        )
      )
    end
  when :Command
    mt[1].each do |k,v|
      case( k )
        when :alias
          Alias.create( found_user, v )
          reply_mail(
            $Config[ 'TITLE' ]+" "+$rev,
            make_mail_body( :Command_alias,
                            [
                              v,
                              Kconv.tojis( summarize( found_user, :this_month, [:seven_days, :this_month] ) ),
                              maddr_token( found_user )
                            ]
            )
          )
      end
    end
  when :Phase_Error
  else
end

# ログファイルがあれば、ログを出力する。
#  ログ行は、メールから抽出したものを使用する。
log_write( Time.now.strftime($Config[ 'LOG_TIME_FORMAT' ])+','+(mt[2]||"nil"), true )

# これで無事終了。
exit 0
