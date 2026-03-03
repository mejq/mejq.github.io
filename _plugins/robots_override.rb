# Jekyll plugin to overwrite robots.txt with custom rules
# This runs after site generation and writes our preferred robots.txt

# override theme-provided robots.txt by writing our own after build

Jekyll::Hooks.register :site, :post_write do |site|
  url = site.config['url'] || ''
  baseurl = site.config['baseurl'] || ''
  sitemap = File.join(url, baseurl, '/sitemap.xml')

  content = <<~ROBOTS
    User-agent: *
    Allow: /

    Sitemap: #{sitemap}
  ROBOTS

  robots_path = File.join(site.dest, 'robots.txt')
  File.write(robots_path, content)
end
