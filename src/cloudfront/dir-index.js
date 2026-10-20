// CloudFront Function (viewer request): serve directory URLs from their index.html.
// default_root_object only applies to "/", so "/ops" and "/ops/" would be 403s.
function handler(event) {
  var request = event.request;
  var uri = request.uri;

  if (uri.endsWith('/')) {
    request.uri = uri + 'index.html';
  } else if (uri.lastIndexOf('.') < uri.lastIndexOf('/')) {
    // No file extension in the last path segment: treat it as a directory.
    request.uri = uri + '/index.html';
  }
  return request;
}
