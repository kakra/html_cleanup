require 'nokogiri'
require 'cssmin'
require 'jsmin'

class HtmlCleanupFilter

  def self.filter(controller)
    case controller.request.format
    when %r{^text/(html|xml|rss)}
      return if controller.response.body.length == 0
      old_size = controller.response.body.length.to_f

      # load the document tree with nokogiri
      body = Nokogiri::HTML.parse(controller.response.body)

      # remove bogus elements
      body.traverse do |e|
        case e.class
        when Nokogiri::XML::Comment
          e.remove unless /^\[if/ === e.content
        end
      end

      # minify special attributes
      %w{class alt title style content}.each do |attr|
        body.search("*[#{attr}]").each { |e| e[attr] = e[attr].gsub(/\s+/m, " ").strip.chomp }
      end

      # minify styles in attributes
      body.search("*[style]").each do |e| 
        e["style"] = e["style"].
          gsub(/([:;,])\s+/m, "\\1").
          gsub(/;+/, ";").
          strip.chomp.
          gsub(/;+$/m, "")
      end

      # minify inline styles with CSSMin
      body.search("style").each { |e| e.content = CSSMin::minify(e.content).strip.chomp }

      # minify javascripts in attributes
      %w{onload onselect onchange onfocus onblur onclick onmouseover onmouseout}.each do |attr|
        body.search("*[#{attr}]").each { |e| e[attr] = JSMin::minify(e[attr]).strip.chomp }
      end

      # minify inline javascripts with JSMin
      body.search("script[type='text/javascript']").each { |e| e.content = JSMin::minify(e.content).strip.chomp }

      # squeeze whitespace
      body = body.to_html.
        gsub(/>\s+(\S[\s\S]*?)?\s+</m, '> \1 <').
        gsub(/>\s+(\S[\s\S]*?)?</m, '> \1<').
        gsub(/>(\S[\s\S]*?)?\s+</m, '>\1 <').
        gsub(/>\s+</m, "> <").
        strip.chomp

      controller.response.body = body
      percent = 100 * (1 - controller.response.body.length / old_size)
      controller.logger.debug "Response body cleanup: #{controller.request.format} code was reduced by %0.1f%%" % percent
    end
  end
end
