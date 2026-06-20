import Foundation

public struct ReaderArticle: Codable, Equatable, Sendable {
  public var url: URL
  public var domain: String
  public var title: String
  public var byline: String?
  public var language: String?
  public var direction: String
  public var contentHTML: String
  public var textContent: String?
  public var excerpt: String?
  public var siteName: String?
  public var publishedTime: String?
  public var cspMetaTags: [String]

  public init(
    url: URL,
    domain: String,
    title: String,
    byline: String? = nil,
    language: String? = nil,
    direction: String = "auto",
    contentHTML: String,
    textContent: String? = nil,
    excerpt: String? = nil,
    siteName: String? = nil,
    publishedTime: String? = nil,
    cspMetaTags: [String] = []
  ) {
    self.url = url
    self.domain = domain
    self.title = title
    self.byline = byline
    self.language = language
    self.direction = direction
    self.contentHTML = contentHTML
    self.textContent = textContent
    self.excerpt = excerpt
    self.siteName = siteName
    self.publishedTime = publishedTime
    self.cspMetaTags = cspMetaTags
  }
}

extension ReaderArticle {
  init?(javascriptObject object: Any) {
    guard let dictionary = object as? [String: Any],
      let urlString = dictionary["url"] as? String,
      let url = URL(string: urlString),
      let title = dictionary["title"] as? String,
      let contentHTML = dictionary["contentHTML"] as? String
    else {
      return nil
    }

    let domain = (dictionary["domain"] as? String) ?? url.host ?? ""
    let direction = (dictionary["direction"] as? String) ?? "auto"

    self.init(
      url: url,
      domain: domain,
      title: title,
      byline: dictionary["byline"] as? String,
      language: dictionary["language"] as? String,
      direction: direction,
      contentHTML: contentHTML,
      textContent: dictionary["textContent"] as? String,
      excerpt: dictionary["excerpt"] as? String,
      siteName: dictionary["siteName"] as? String,
      publishedTime: dictionary["publishedTime"] as? String,
      cspMetaTags: dictionary["cspMetaTags"] as? [String] ?? []
    )
  }
}
