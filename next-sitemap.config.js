module.exports = {
  siteUrl: process.env.SITE_URL || 'https://xapzap.com',
  generateRobotsTxt: true,
  sitemapSize: 5000,
  changefreq: 'daily',
  priority: 0.7,
  exclude: ['/admin*', '/private*'],
}
