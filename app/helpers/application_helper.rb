module ApplicationHelper
  def render_markdown(text)
    renderer = Redcarpet::Render::HTML.new(filter_html: true, hard_wrap: true)
    markdown = Redcarpet::Markdown.new(renderer, fenced_code_blocks: true, tables: true, autolink: true)
    markdown.render(text.to_s)
  end
end
