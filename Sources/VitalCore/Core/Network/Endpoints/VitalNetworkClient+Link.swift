import Get
import Foundation

public extension VitalNetworkClient {
  class Link {
    let client: VitalNetworkClient
    let path = "link"
    
    init(client: VitalNetworkClient) {
      self.client = client
    }
  }
  
  var link: Link {
    .init(client: self)
  }
}

public extension VitalNetworkClient.Link {
  
  func createConnectedSource(
    _ userId: UUID,
    provider: Provider
  ) async throws -> Void {

    let path = "/\(self.client.apiVersion)/\(path)/provider/manual/\(provider.rawValue)"
    
    let payload = CreateConnectionSourceRequest(userId: userId)
    let request = Request<Void>.post(path, body: payload)
    
    try await self.client.apiClient.send(request)
  }
  
  func createConnectedSource(
    for provider: Provider
  ) async throws -> Void {
    
    guard let userId = self.client.userId else {
      fatalError("VitalNetwork's `userId` hasn't been set. Please call `setUserId`")
    }
    
    try await createConnectedSource(userId, provider: provider)
  }
}
