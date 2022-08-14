import Foundation
import os.log

struct Credentials: Equatable, Hashable {
  let apiKey: String
  let environment: Environment
}

struct VitalCoreConfiguration {
  var logger: Logger? = nil
  let apiVersion: String
  let apiClient: APIClient
  let environment: Environment
  let storage: VitalCoreStorage
}

struct VitalCoreSecurePayload: Codable {
  let configuration: VitalClient.Configuration
  let apiVersion: String
  let apiKey: String
  let environment: Environment
}

public enum Environment: Equatable, Hashable, Codable {
  public enum Region: Equatable, Hashable, Codable {
    case eu
    case us
    
    var name: String {
      switch self {
        case .eu:
          return "eu"
        case .us:
          return "us"
      }
    }
  }
  
  case dev(Region)
  case sandbox(Region)
  case production(Region)
  
  var host: String {
    switch self {
      case .dev(.eu):
        return "https://api.dev.eu.tryvital.io"
      case .dev(.us):
        return "https://api.dev.tryvital.io"
      case .sandbox(.eu):
        return "https://api.sandbox.eu.tryvital.io"
      case .sandbox(.us):
        return "https://api.sandbox.tryvital.io"
      case .production(.eu):
        return "https://api.eu.tryvital.io"
      case .production(.us):
        return "https://api.tryvital.io"
    }
  }
  
  var name: String {
    switch self {
      case .dev:
        return "dev"
      case .sandbox:
        return "sandbox"
      case .production:
        return "production"
    }
  }
  
  var region: Region {
    switch self {
      case .dev(let region):
        return region
      case .sandbox(let region):
        return region
      case .production(let region):
        return region
    }
  }
}

private let core_secureStorageKey: String = "core_secureStorageKey"
private let user_secureStorageKey: String = "user_secureStorageKey"

public let health_secureStorageKey: String = "health_secureStorageKey"

public class VitalClient {
  
  private let secureStorage: VitalSecureStorage
  let configuration: ProtectedBox<VitalCoreConfiguration>
  let userId: ProtectedBox<UUID>
  
  private static var client: VitalClient?

  public static var shared: VitalClient {
    guard let value = client else {
      let newClient = VitalClient()
      return newClient
    }
    
    return value
  }
  
  public static func configure(
    apiKey: String,
    environment: Environment,
    configuration: Configuration = .init()
  ) {
    Task.detached(priority: .high) {
      await self.shared.setConfiguration(
        apiKey: apiKey,
        environment: environment,
        configuration: configuration
      )
    }
  }
  
  public static func automaticConfiguration() {
    Task.detached(priority: .high) {
      do {
        if let payload: VitalCoreSecurePayload = try shared.secureStorage.get(key: core_secureStorageKey) {
          configure(
            apiKey: payload.apiKey,
            environment: payload.environment,
            configuration: payload.configuration
          )
        }
        
        if let userId: UUID = try shared.secureStorage.get(key: user_secureStorageKey) {
          setUserId(userId)
        }
      }
      catch {
        /// Bailout, there's nothing else to do here.
      }
    }
  }
  
  init(
    secureStorage: VitalSecureStorage = .init(keychain: .live),
    configuration: ProtectedBox<VitalCoreConfiguration> = .init(),
    userId: ProtectedBox<UUID> = .init()
  ) {
    self.secureStorage = secureStorage
    self.configuration = configuration
    self.userId = userId
    
    VitalClient.client = self
  }
  
  func setConfiguration(
    apiKey: String,
    environment: Environment,
    configuration: Configuration,
    storage: VitalCoreStorage = .init(storage: .live),
    apiVersion: String = "v2"
  ) async {
    var logger: Logger?
    
    if configuration.logsEnable {
      logger = Logger(subsystem: "vital", category: "vital-network-client")
    }
    
    let securePayload = VitalCoreSecurePayload(
      configuration: configuration,
      apiVersion: apiVersion,
      apiKey: apiKey,
      environment: environment
    )
    
    do {
      try secureStorage.set(value: securePayload, key: core_secureStorageKey)
    }
    catch {
      logger?.info("We weren't able to securely store VitalCoreSecurePayload: \(error.localizedDescription)")
    }
    
    logger?.info("VitalClient setup for environment \(String(describing: environment))")
    
    let apiClientDelegate = VitalClientDelegate(
      environment: environment,
      logger: logger,
      apiKey: apiKey
    )
    
    let apiClient = APIClient(baseURL: URL(string: environment.host)!) { configuration in
      configuration.delegate = apiClientDelegate
      
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.keyEncodingStrategy = .convertToSnakeCase
      
      let decoder = JSONDecoder()
      decoder.keyDecodingStrategy = .convertFromSnakeCase
      decoder.dateDecodingStrategy = .iso8601
      
      configuration.encoder = encoder
      configuration.decoder = decoder
    }
    
    let coreConfiguration = VitalCoreConfiguration(
      logger: logger,
      apiVersion: apiVersion,
      apiClient: apiClient,
      environment: environment,
      storage: storage
    )
    
    await self.configuration.set(value: coreConfiguration)
  }
  
  public static func setUserId(_ userId: UUID) {
    Task.detached(priority: .high) {
      await VitalClient.shared.userId.set(value: userId)
      
      let configuration = await VitalClient.shared.configuration.get()
      
      do {
        try shared.secureStorage.set(value: userId, key: user_secureStorageKey)
      }
      catch {
        configuration.logger?.info("We weren't able to securely store VitalCoreSecurePayload: \(error.localizedDescription)")
      }
    }
  }
  
  public func checkConnectedSource(for provider: Provider) async throws {
    let userId = await userId.get()
    let storage = await configuration.get().storage
    
    guard storage.isConnectedSourceStored(for: userId, with: provider) == false else {
      return
    }
    
    let connectedSources = try await self.user.userConnectedSources()
    if connectedSources.contains(provider) == false {
      try await self.link.createConnectedSource(userId, provider: provider)
    }
    
    storage.storeConnectedSource(for: userId, with: provider)
  }
  
  public func cleanUp() {
    Task.detached(priority: .high) {
      /// Here we remove the following:
      /// 1) Anchor values we are storing for each `HKSampleType`.
      /// 2) Stage for each `HKSampleType`.
      ///
      /// We might be able to derive 2) from 1)?
      await self.configuration.get().storage.clean()
      
      self.secureStorage.clean(key: core_secureStorageKey)
      self.secureStorage.clean(key: health_secureStorageKey)
      self.secureStorage.clean(key: user_secureStorageKey)
      
      await self.userId.clean()
    }
  }
}

public extension VitalClient {
  struct Configuration: Codable {
    public let logsEnable: Bool
    
    public init(
      logsEnable: Bool = false
    ) {
      self.logsEnable = logsEnable
    }
  }
}
