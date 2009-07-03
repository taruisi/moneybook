# $Id: maillib.rb 101 2009-07-02 04:38:42Z taruisi $

require 'rubygems'
require 'tmail'
require 'net/smtp'
require 'kconv'

IM = TMail::Mail.parse($stdin.read)
if $Config['DUMP_MAIL'] then
  log_write( IM.encoded, true, "mail.#{$$.to_s}.in.txt" )
end

def mail
  return IM
end

def maddr_encode
  IM.from.to_s.gsub('@','_at_').gsub('.','_')
end

def maddr_token( user=nil )
  if user then
    maddr = user.mailaddress.to_s
  else
    maddr = IM.from.to_s
  end
  Digest::MD5.hexdigest( maddr.crypt(SALT) )
end

def reply_mail( subject, body) 

=begin
Thanks to http://code.nanigac.com/source/view/339
=end

  mail = TMail::Mail.new 

  mail.to =       IM.from.to_s
  mail.from =     $Config[ 'TARGET' ]
  mail.reply_to = $Config[ 'TARGET' ]
  mail.sender =   $Config[ 'SENDER' ]

  work =          Kconv.tojis(subject).split(//,1).pack('m').chomp 
  mail.subject =  "=?ISO-2022-JP?B?"+work.gsub('\n', '')+"?=" 
  mail.body =     Kconv.tojis(body) 

  mail.date =     Time.now
  mail.mime_version = '1.0' 
  mail.set_content_type 'text', 'plain', {'charset'=>'iso-2022-jp'} 

  mail.write_back

  if $Config['DUMP_MAIL'] then
    log_write( mail.encoded, true, "mail.#{$$.to_s}.out.txt" )
  else
    Net::SMTP.start( $Config[ 'SMTP_SERVER' ] ) do |smtp| 
      smtp.sendmail( mail.encoded, mail.from, mail.to ) 
    end
  end
end

def get_mail_type( user )
  found_token = false
  found_user = user
  found_error = false
  items       = Array.new
  replies     = Array.new
  new_item    = Array.new
  command     = Hash.new

  if ($Config[ 'ACCOUNT_CHECK' ] && ($Config[ 'ACCOUNT_CHECK' ]!=IM.to.to_s)) then
    return [:NOP, nil, "Account Check Failed Req:#{$Config[ 'ACCOUNT_CHECK' ]} Mail:#{IM.to.to_s}" ] 
  end

  Kconv.toutf8(IM.body).split("\n").each do |e|
    if /\[(.+)\]/ =~ e then
      item = $1.strip
      replies << e.chomp
      if item==maddr_token( user ) then
        found_token = true
        next
      end
      if found_user then
        unless Section.check_section( found_user, item ) then
          new_item << item if ($1!~/項目名/ && found_token)
        end
        if /\[(.+)\] */=~e then
          iname = ($1+' ').strip
          ival  = 0.0
          if /^(-?[0-9]+\.?[0-9]*)/ =~ $' then
            ival = $1.to_f
          end
          i = [ iname, ival ]
          if /^\{(.+)\}/ =~ $' then i[2] = $1 end
          if ival==0.0 && i[2] then i[0]="BLOG" end
          if (i[0]=~/項目名/) or (i[0]!~/積立/ and i[1]<0) then
          else
            items << i
          end
#        else
#          puts e
#          replies[-1]="#{e}!"
#          found_error = true
        end
      end
    else
#       puts e
      if /^=([A-Za-z0-9\.]+@[A-Za-z0-9\.]+)/ =~ e then
        command[ :alias ] = $1
      end
    end
  end
  new_item.each { |e| Section.create( found_user, e ) }
		
  unless found_user then
#    puts IM.subject
    if Kconv.toutf8(IM.subject)=~/登録/ then
      ret = [ :Phase_1, nil ]
    else
      if found_token then
        ret = [ :Phase_2, nil ]
      else
        return [ :NOP, nil, "No token found and no User found #{Kconv.toutf8(IM.subject)}" ]
      end
    end
  else
    if found_token then
      if IM.subject==Kconv.tojis('削除 ').strip then
        ret = [ :Destroy_Newest, nil ]
      elsif IM.subject==Kconv.tojis('予算 ').strip then
        items.each { |e| e[0]=nil if Kconv.toutf8(e[0]).strip==Kconv.toutf8("合計 ").strip }
        ret = [ :Set_Limits, items ]
      elsif items.size==0 then
        ret = [ :Phase_2, nil ]
      else
        if found_error then
          ret = [ :Phase_Error, replies ]
        else
          if command.size>0 then
            ret = [ :Command, command ]
          else
            ret = [ :Phase_3, items ]
          end
        end
      end
    else
      return [ :NOP, nil, "No appropreate user token found" ]
    end
  end
  log_lines = [ ret[0].to_s, mail.from.to_s, "token=#{found_token.to_s}", "err=#{found_error.to_s}" ]
  log_lines += items.map{ |e| "#{e[0]}=#{e[1].to_s}" } if ret[0]==:Phase_3
  return (ret<<log_lines.join(','))

end
