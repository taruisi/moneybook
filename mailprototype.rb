# $Id: mailprototype.rb 96 2009-06-08 04:13:10Z taruisi $
# メールのひな形宣言

def make_mail_body( phase, parm=[] )

  parm += [ '', '' ]
  uparm = parm.map do |e|
    if e.class==String then Kconv.toutf8(e) else e end
  end

  rev_name = "小遣い帳  #{$rev}"
  case( phase )
    when :Phase_1
      mailbody = <<EOPH1
このメールをそのまま返信してください。

[%s]

#{rev_name}
EOPH1
    when :Phase_2
      mailbody = <<EOPH2
このメールに次のような項目を記入して返信してください。
[項目名] 金額

[%s]

#{rev_name}
EOPH2
    when :Phase_3
      mailbody = <<EOPH3
今の状況は以下のとおりです。

%s

[%s]

#{rev_name}
EOPH3
    when :Delete_newest
      mailbody = <<EODELN
以下の登録を削除しました。

%s : %d

%s

[%s]

#{rev_name}
EODELN
    when :Command_alias
      mailbody = <<CMDALS
別名を登録しました: %s

%s

[%s]

#{rev_name}
CMDALS
  end
  return( Kconv.tojis( mailbody % uparm ) )
end
