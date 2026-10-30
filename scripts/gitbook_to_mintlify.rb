#!/usr/bin/env ruby
# frozen_string_literal: true

# One-off migration of the GitBook repo (DeliveryVip/docs-api) into this Mintlify project.
# Safe to re-run: it regenerates every page, images/ and docs.json from the GitBook source.
#
#   ruby scripts/gitbook_to_mintlify.rb ../ApiDocs .

require "yaml"
require "json"
require "fileutils"
require "pathname"
require "nokogiri"

class GitbookToMintlify
  # README.md (the GitBook landing page) is replaced by the hand-written home in index.mdx.
  SKIP = %w[SUMMARY.md CLAUDE.md README.md].freeze
  HANDWRITTEN = %w[index.mdx].freeze
  CALLOUTS = { "info" => "Info", "warning" => "Warning", "danger" => "Danger", "success" => "Check" }.freeze
  EMOJI = { ":new:" => "🆕", ":warning:" => "⚠️" }.freeze
  IMAGE_EXTENSIONS = %w[.png .jpg .jpeg .gif .svg .webp].freeze

  OPERATION = /\{% openapi-operation spec="[^"]*" path="([^"]*)" method="([^"]*)" %\}\s*\[[^\]]*\]\(([^)]*)\)\s*\{% endopenapi-operation %\}\n?/
  CONTENT_REF = /\{% content-ref url="([^"]*)" %\}\s*\[([^\]]*)\]\([^)]*\)\s*\{% endcontent-ref %\}/

  SECTION_TITLES = {
    "Events" => "Eventos", "List" => "Listagem", "Lists" => "Listagens", "Details" => "Detalhes", "Actions" => "Ações",
    "Actions - Tabs" => "Ações de comandas", "Actions - Places" => "Ações de places",
    "Actions - Merchant" => "Cadastro", "Actions - Resale" => "Cadastro", "Actions - Member" => "Membros",
    "Actions - Subscription" => "Assinatura", "Actions - Features" => "Recursos",
    "Actions - Application Permission" => "Permissão de aplicativos"
  }.freeze

  # Font Awesome icons by tab and group name; a theme keeps its icon wherever it shows up.
  ICONS = {
    "Início" => "house", "Merchant API" => "store", "Open Delivery" => "right-left", "Fidelidade" => "gift",
    "Partner API" => "handshake", "Changelog" => "clock-rotate-left",
    "Comece aqui" => "flag", "Primeiros passos" => "rocket", "Conceitos" => "book", "Referência" => "code",
    "Autenticação" => "key", "Visão geral" => "compass", "Guias" => "map", "Pedidos" => "receipt",
    "Catálogo" => "utensils", "Indoor" => "chair", "Descontos" => "tag", "Ferramentas" => "wrench",
    "Contrato do operador" => "file-contract", "Configuração do programa" => "sliders",
    "Rotas do operador" => "server", "Lojas" => "shop", "Revendas" => "users", "Planos" => "layer-group",
    "Faturas" => "file-invoice-dollar", "Cadastro" => "user-plus"
  }.freeze

  LOYALTY_OPERATOR_SPEC = "https://app.deliveryvip.com.br/swaggers/loyalty_operator.yaml"

  # One tab per product. A ".md" string is a SUMMARY.md entry with its subtree, `page:` takes the
  # page alone, `entry:` + `title:` renames the group the entry becomes; other strings pass through.
  LAYOUT = [
    { tab: "Início", groups: [
      { group: "Início", pages: ["index"] },
      { entry: "inicio/primeiros-passos/README.md", title: "Primeiros passos" },
      { entry: "inicio/conceitos/README.md", title: "Conceitos" },
      { group: "Referência", pages: [{ entry: "reference/merchant/v3/authentication.md", title: "Autenticação" }] }
    ] },
    { tab: "Merchant API", groups: [
      { group: "Visão geral", pages: [{ page: "guides/merchant/README.md" }, "guides/merchant/events.md", "guides/merchant/webhooks.md"] },
      { entry: "guides/merchant/order/README.md", title: "Pedidos" },
      { entry: "guides/merchant/catalog-and-services/README.md", title: "Catálogo" },
      { entry: "guides/merchant/indoor/README.md", title: "Indoor" },
      { entry: "guides/merchant/discount/README.md", title: "Descontos" },
      { entry: "guides/merchant/tools/README.md", title: "Ferramentas" },
      { group: "Referência", pages: [
        { entry: "reference/merchant/v3/orders.md", title: "Pedidos" },
        { entry: "reference/merchant/v3/catalog-and-services.md", title: "Catálogo" },
        { entry: "reference/merchant/v3/indoor.md", title: "Indoor" },
        { entry: "reference/merchant/v3/discounts.md", title: "Descontos" },
        { entry: "reference/merchant/v3/tools.md", title: "Ferramentas" }
      ] }
    ] },
    { tab: "Open Delivery", groups: [
      { group: "Visão geral", pages: [{ page: "guides/open-delivery/README.md" }, "guides/open-delivery/primeiros-passos.md"] },
      { group: "Guias", pages: %w[onboarding-de-lojas catalogo recebendo-eventos ciclo-de-vida-do-pedido].map { |p| "guides/open-delivery/#{p}.md" } },
      { group: "Referência", pages: ["guides/open-delivery/referencia-rapida.md"] }
    ] },
    { tab: "Fidelidade", groups: [
      { group: "Visão geral", pages: [{ page: "guides/merchant/loyalty/README.md" }, "guides/merchant/loyalty/primeiros-passos.md"] },
      { group: "Guias", pages: ["guides/merchant/loyalty/ativando-o-programa.md", "guides/merchant/loyalty/acumulo.md"] },
      { entry: "guides/merchant/loyalty/contrato-do-operador/README.md", title: "Contrato do operador" },
      { group: "Referência", pages: [
        "guides/merchant/loyalty/referencia-rapida.md",
        { entry: "reference/merchant/v3/loyalty.md", title: "Configuração do programa" },
        { group: "Rotas do operador", openapi: LOYALTY_OPERATOR_SPEC, pages: [
          "GET /v1/loyalty/ping",
          "POST /v1/loyalty/accounts:link",
          "GET /v1/loyalty/accounts/{accountId}",
          "POST /v1/loyalty/redemptions",
          "POST /v1/loyalty/redemptions/{redemptionId}/reversal"
        ] }
      ] }
    ] },
    { tab: "Partner API", groups: [
      { group: "Visão geral", pages: [{ page: "guides/partner/README.md" }] },
      { entry: "guides/partner/merchant/README.md", title: "Lojas" },
      { entry: "guides/partner/resale/README.md", title: "Revendas" },
      { entry: "guides/partner/plans/README.md", title: "Planos" },
      { entry: "guides/partner/invoices/README.md", title: "Faturas" },
      { entry: "guides/partner/signup/README.md", title: "Cadastro" },
      { group: "Referência", pages: [
        { entry: "reference/partner/v2/merchant.md", title: "Lojas" },
        { entry: "reference/partner/v2/resale.md", title: "Revendas" },
        { entry: "reference/partner/v2/plans.md", title: "Planos" },
        { entry: "reference/partner/v2/invoices.md", title: "Faturas" },
        { entry: "reference/partner/v2/signup.md", title: "Cadastro" }
      ] }
    ] },
    { tab: "Changelog", groups: [
      { group: "Changelog", pages: ["changelog.md", "deprecations.md"] }
    ] }
  ].freeze

  def initialize(src, dest)
    @src = Pathname(src).expand_path
    @dest = Pathname(dest).expand_path
    @pages = {}
  end

  def run
    sources.each { |rel| @pages[rel] = parse(rel) }
    @pages.each { |rel, page| page[:body] = convert(rel, page) }
    clean_output
    @pages.each { |rel, page| write(rel, page) }
    copy_images
    write_docs_json
  end

  private

  def sources
    Dir.chdir(@src) { Dir.glob("**/*.md").reject { |f| SKIP.include?(f) || f.start_with?(".") }.sort }
  end

  def parse(rel)
    text = File.read(@src / rel)
    meta = {}
    if text.start_with?("---\n")
      _, front, text = text.split(/^---\s*\n/, 3)
      meta = YAML.safe_load(front) || {}
    end
    title = nil
    text = text.sub(/\A\s*# (.+)\n/) { title = $1.strip and "" }
    { title: clean_title(title || File.basename(rel, ".md")), description: meta["description"]&.strip, body: text, operations: [] }
  end

  def clean_title(title)
    title.sub(/\A[^\p{L}\p{N}]+/, "").gsub(/<[^>]+>/, "").strip
  end

  def convert(rel, page)
    body = extract_operations(page[:body], page)
    body = convert_content_refs(rel, body)
    body = convert_blocks(body)
    body = convert_html(rel, body)
    body = convert_links(rel, body)
    EMOJI.each { |code, emoji| body = body.gsub(code, emoji) }
    body = escape_mdx(body)
    body.gsub(/\n{3,}/, "\n\n").strip
  end

  # Reference pages become an overview (the prose) plus one generated page per operation.
  def extract_operations(body, page)
    body = body.gsub(OPERATION) do
      match = $~
      section = match.pre_match.scan(/^## (.+)$/).last&.first
      page[:operations] << { spec: match[3], method: match[2].upcase, path: match[1], section: clean_title(section.to_s) }
      ""
    end
    return body if page[:operations].empty?

    loop do
      pruned = body.gsub(/^#+ .+\n\s*(?=^#+ |\z)/, "")
      break body if pruned == body

      body = pruned
    end
  end

  def convert_content_refs(rel, body)
    body.gsub(/(?:#{CONTENT_REF}\s*)+/) do |run|
      cards = run.scan(CONTENT_REF).map { |url, text| card(resolve(rel, url), text) }
      "<CardGroup cols={2}>\n#{cards.join("\n")}\n</CardGroup>\n\n"
    end
  end

  def card(href, text, description = nil)
    target = page_at(href)
    title = target&.dig(:title) || text
    description ||= target&.dig(:description)
    %(<Card title="#{attr(title)}" href="#{href}">#{description&.gsub(/\s+/, " ")}</Card>)
  end

  def convert_blocks(body)
    callouts = []
    body.lines.map do |line|
      case line
      when /\A\s*\{% hint(?: style="(\w+)")? %\}/ then callouts << CALLOUTS.fetch($1 || "info") and "<#{callouts.last}>\n"
      when /\A\s*\{% endhint %\}/ then "</#{callouts.pop}>\n"
      when /\A\s*\{% tabs %\}/ then "<Tabs>\n"
      when /\A\s*\{% endtabs %\}/ then "</Tabs>\n"
      when /\A\s*\{% tab title="([^"]*)" %\}/ then %(<Tab title="#{attr($1)}">\n)
      when /\A\s*\{% endtab %\}/ then "</Tab>\n"
      when /\A\s*\{% (?:end)?code\b[^%]*%\}/ then ""
      else line
      end
    end.join
  end

  def convert_html(rel, body)
    body = body.gsub(%r{<pre class="language-(\w+)">.*?</pre>}m) { "```#{$1}\n#{fragment($&).text.strip}\n```" }
    body = body.gsub(%r{<table[^>]*>.*?</table>}m) { "\n#{convert_table(rel, fragment($&).at('table'))}\n" }
    body = body.gsub(%r{<figure>.*?</figure>}m) { convert_figure(fragment($&)) }
    body = body.gsub(%r{\s*<a href="#[^"]*" id="[^"]*"></a>}, "")
    body = body.gsub(%r{<a href="[^"]*">.*?</a>}m) { inline_md(fragment($&)) }
    body = body.gsub(%r{<mark[^>]*>(.*?)</mark>}m, '\1')
    body = body.gsub(/<br\s*\/?>/, "<br />")
    body = body.gsub(/<img ([^>]*?)\s*\/?>/, '<img \1 />')
    body.gsub(%r{<(https?://[^>\s]+)>}, '[\1](\1)')
  end

  def convert_table(rel, table)
    return convert_cards(rel, table) if table["data-view"] == "cards"

    rows = table.css("tr").map { |tr| tr.css("th, td").to_a }
    rows.shift if table.key?("data-header-hidden")
    header, *data = rows
    aligns = header.each_index.map do |i|
      case (data.first&.[](i) || header[i])["align"]
      when "center" then ":-:"
      when "right" then "--:"
      else "---"
      end
    end
    [header, aligns, *data].map do |cells|
      cells = cells.map { |cell| cell_md(cell) } unless cells == aligns
      "| #{cells.join(' | ')} |"
    end.join("\n")
  end

  def convert_cards(rel, table)
    cards = table.css("tbody tr").map do |tr|
      title, description, target = tr.css("td")
      card(resolve(rel, target.at("a")["href"]), inline_md(title).delete("*").strip, inline_md(description).strip)
    end
    "<CardGroup cols={2}>\n#{cards.join("\n")}\n</CardGroup>"
  end

  def convert_figure(figure)
    img = figure.at("img")
    caption = figure.at("figcaption")&.text&.strip
    open = caption.to_s.empty? ? "<Frame>" : %(<Frame caption="#{attr(caption)}">)
    %(#{open}\n  <img src="#{img['src']}" alt="#{attr(img['alt'].to_s)}" />\n</Frame>)
  end

  def cell_md(cell)
    inline_md(cell).strip.gsub(/\s*\n\s*/, "<br />").gsub("|", "\\|")
  end

  def inline_md(node)
    node.children.map do |child|
      case child.name
      when "text" then child.text.gsub("<", "&lt;")
      when "strong", "b" then wrap("**", inline_md(child))
      when "em", "i" then wrap("*", inline_md(child))
      when "code" then "`#{child.text}`"
      when "a" then "[#{inline_md(child).strip}](#{child['href']})"
      when "br" then "\n"
      when "p" then "#{inline_md(child)}\n"
      when "img" then %(<img src="#{child['src']}" alt="#{attr(child['alt'].to_s)}" />)
      else inline_md(child)
      end
    end.join
  end

  def wrap(mark, text)
    text.strip.empty? ? text : "#{mark}#{text.strip}#{mark}"
  end

  def convert_links(rel, body)
    body = body.gsub(/\]\(([^)\s]+)\)/) { "](#{resolve(rel, $1)})" }
    body.gsub(/\b(src|href)="([^"]*)"/) { %(#{$1}="#{resolve(rel, $2)}") }
  end

  def resolve(rel, url)
    return url if url.match?(%r{\A(?:[a-z]+:|#|/)}i)

    path, anchor = url.gsub("%20", " ").split("#", 2)
    target = (Pathname(rel).dirname / path).cleanpath.to_s
    return "/images/#{image_name(target)}" if target.include?(".gitbook/assets/")

    target = target.delete_suffix(".md").sub(%r{(?:\A|/)README\z}, "").sub(/\A\.\z/, "")
    "/#{target}#{"##{anchor}" if anchor}"
  end

  def page_at(href)
    route = href.split("#").first.delete_prefix("/")
    @pages.find { |rel, _| route_of(rel) == route }&.last
  end

  def route_of(rel)
    rel.delete_suffix(".md").sub(%r{(?:\A|/)README\z}, "")
  end

  def nav_path(rel)
    rel.delete_suffix(".md").sub(/README\z/, "index")
  end

  # Outside code, MDX reads { } as expressions and < as JSX.
  def escape_mdx(body)
    fenced = false
    body.lines.map do |line|
      fenced = !fenced if line.match?(/\A\s*(```|~~~)/)
      next line if fenced || line.match?(/\A\s*(```|~~~)/) || line.match?(%r{\A\s*</?[A-Z]})

      line.split(/(`[^`]*`)/).each_with_index.map do |part, i|
        i.odd? ? part : part.gsub(/[{}]/) { "\\#{$&}" }.gsub(/<(?![A-Za-z\/!])/, "&lt;")
      end.join
    end.join
  end

  def write(rel, page)
    front = { "title" => page[:title], "description" => page[:description] }.compact
    path = @dest / "#{nav_path(rel)}.mdx"
    FileUtils.mkdir_p(path.dirname)
    File.write(path, "#{front.to_yaml}---\n\n#{page[:body]}\n")
  end

  def clean_output
    top_dirs = @pages.keys.map { |rel| rel.split("/").first }.select { |d| (@dest / d).directory? }.uniq
    FileUtils.rm_rf(top_dirs.map { |d| @dest / d } + [@dest / "images"])
    Dir.glob(@dest / "*.mdx").each { |f| FileUtils.rm(f) unless HANDWRITTEN.include?(File.basename(f)) }
  end

  def copy_images
    FileUtils.mkdir_p(@dest / "images")
    Dir.glob(@src / ".gitbook/assets/*").each do |file|
      next unless IMAGE_EXTENSIONS.include?(File.extname(file).downcase)

      FileUtils.cp(file, @dest / "images" / image_name(file))
    end
  end

  def image_name(path)
    File.basename(path).downcase.gsub(/[^a-z0-9.]+/, "-")
  end

  def attr(text)
    text.gsub('"', "&quot;")
  end

  def fragment(html)
    Nokogiri::HTML::DocumentFragment.parse(html)
  end

  def write_docs_json
    @items = summary_items
    config = JSON.parse(File.read(@dest / "docs.json"))
    tabs = LAYOUT.map { |tab| { tab: tab[:tab], groups: tab[:groups].map { |group| nav_group(group) } } }
    config["navigation"] = { "tabs" => with_icons(tabs) }
    File.write(@dest / "docs.json", "#{JSON.pretty_generate(config)}\n")
  end

  def with_icons(node)
    case node
    when Array then node.map { |child| with_icons(child) }
    when Hash
      name = node[:tab] || node[:group]
      icon = ICONS[name]
      node = node.transform_values { |value| value.is_a?(Array) ? with_icons(value) : value }
      icon ? node.merge(icon: icon) : node
    else node
    end
  end

  def summary_items
    stack = []
    File.readlines(@src / "SUMMARY.md").each_with_object({}) do |line, items|
      next unless line =~ /\A(\s*)\* \[(.+?)\]\((.+?)\)/

      item = { title: clean_title($2), rel: $3, children: [] }
      depth = $1.size / 2
      stack[depth] = item
      stack[depth - 1][:children] << item if depth.positive?
      items[item[:rel]] = item
    end
  end

  def nav_group(group)
    if group[:entry]
      entry = entry(@items.fetch(group[:entry]), group[:title])
      return entry.is_a?(String) ? { group: group[:title], pages: [entry] } : entry
    end

    { group: group[:group], openapi: group[:openapi], pages: group[:pages].map { |item| nav_item(item) } }.compact
  end

  def nav_item(item)
    case item
    in String if item.end_with?(".md") then entry(@items.fetch(item))
    in String then item
    in { page: } then nav_path(page)
    in { entry:, title: } then entry(@items.fetch(entry), title)
    in { group: } then nav_group(item)
    end
  end

  def entry(item, title = item[:title])
    page = @pages.fetch(item[:rel])
    own = [nav_path(item[:rel])]
    return own.first if item[:children].empty? && page[:operations].empty?

    group = { group: title, pages: own + item[:children].map { |child| entry(child) } }
    return group if page[:operations].empty?

    specs = page[:operations].map { |op| op[:spec] }.uniq
    raise "#{item[:rel]} mixes OpenAPI specs: #{specs.join(', ')}" unless specs.one?

    spec = specs.first
    sections = page[:operations].chunk_while { |a, b| a[:section] == b[:section] }.map do |ops|
      endpoints = ops.map { |op| "#{op[:method]} #{op[:path]}" }
      ops.first[:section].empty? ? endpoints : [{ group: SECTION_TITLES.fetch(ops.first[:section], ops.first[:section]), openapi: spec, pages: endpoints }]
    end
    endpoints = sections.flatten(1)
    endpoints = endpoints.first[:pages] if endpoints.one? && endpoints.first.is_a?(Hash)
    # A group-level spec without endpoint pages of its own makes Mintlify list the whole spec.
    group = group.merge(openapi: spec) if endpoints.any?(String)
    group.merge(pages: group[:pages] + endpoints)
  end
end

GitbookToMintlify.new(*ARGV.first(2)).run
