import Foundation

/// Talks to our own licensing backend at `alt-tab.app/v1/license/*`. Provider-agnostic:
/// the backend's active payment provider is a deployment-time choice that this client
/// never sees. Same wire format regardless of who's actually handling payments.
struct RemoteLicenseClient: LicenseAPI {
    let baseUrl: String
    let keychain: Keychain

    init(baseUrl: String, keychain: Keychain) {
        self.baseUrl = baseUrl
        self.keychain = keychain
    }

    func activate(_ licenseKey: String, completion: @escaping (Result<ActivateResult, Error>) -> Void) {
        var body: [String: Any] = [
            "license_key": licenseKey,
            "fingerprint": MachineFingerprint.get(keychain: keychain),
        ]
        // Pass the local trial-start timestamp so the backend can report
        // trial-to-paid conversion latency. The backend takes MIN across
        // machines; omitted when nil (e.g. after deactivation clears it).
        if let trialStart = LicenseManager.shared.trialStartDate {
            body["trial_started_at"] = Int(trialStart.timeIntervalSince1970)
        }
        Logger.debug { "alt-tab-backend POST \(baseUrl)/activate" }
        post("activate", body: body) { (result: Result<ActivateResponse, Error>) in
            switch result {
            case .success(let response):
                if response.activated {
                    Logger.debug { "alt-tab-backend activate OK: activated=true, variant_id=\(response.variant_id ?? "nil"), instance_id=\(response.instance_id ?? "nil")" }
                    guard let instanceId = response.instance_id else {
                        completion(.failure(LicenseAPIError.invalidResponse(debugInfo: "missing instance_id")))
                        return
                    }
                    completion(.success(ActivateResult(
                        instanceId: instanceId,
                        variantId: response.variant_id,
                        customerEmail: response.customer_email
                    )))
                    return
                }
                Logger.debug { "alt-tab-backend activate KO: activated=false, error=\(response.error ?? "nil")" }
                switch response.error {
                case "invalid_key":
                    completion(.failure(LicenseAPIError.invalidKey))
                case "seat_limit_exceeded":
                    let instances = (response.instances ?? []).map(\.asActiveInstance)
                    completion(.failure(LicenseAPIError.seatLimitExceeded(instances: instances)))
                case .some(let reason):
                    completion(.failure(LicenseAPIError.activationRejected(reason)))
                case nil:
                    completion(.failure(LicenseAPIError.activationRejected("unknown")))
                }
            case .failure(let error):
                Logger.debug { "alt-tab-backend activate KO: \(error)" }
                completion(.failure(error))
            }
        }
    }

    func validate(_ licenseKey: String, instanceId: String, completion: @escaping (Result<ValidateResult, Error>) -> Void) {
        let body: [String: Any] = [
            "license_key": licenseKey,
            "instance_id": instanceId,
        ]
        Logger.debug { "alt-tab-backend POST \(baseUrl)/validate" }
        post("validate", body: body) { (result: Result<ValidateResponse, Error>) in
            switch result {
            case .success(let response):
                Logger.debug { "alt-tab-backend validate \(response.valid ? "OK" : "KO"): valid=\(response.valid), variant_id=\(response.variant_id ?? "nil")" }
                completion(.success(ValidateResult(valid: response.valid, variantId: response.variant_id)))
            case .failure(let error):
                Logger.debug { "alt-tab-backend validate KO: \(error)" }
                completion(.failure(error))
            }
        }
    }

    func deactivate(_ licenseKey: String, instanceId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let body: [String: Any] = [
            "license_key": licenseKey,
            "instance_id": instanceId,
        ]
        Logger.debug { "alt-tab-backend POST \(baseUrl)/deactivate" }
        post("deactivate", body: body) { (result: Result<DeactivateResponse, Error>) in
            switch result {
            case .success(let response):
                if response.deactivated {
                    Logger.debug { "alt-tab-backend deactivate OK: deactivated=true" }
                    completion(.success(()))
                } else {
                    Logger.debug { "alt-tab-backend deactivate KO: deactivated=false, error=\(response.error ?? "nil")" }
                    completion(.failure(LicenseAPIError.deactivationRejected))
                }
            case .failure(let error):
                Logger.debug { "alt-tab-backend deactivate KO: \(error)" }
                completion(.failure(error))
            }
        }
    }

    private func post<T: Decodable>(_ endpoint: String, body: [String: Any], completion: @escaping (Result<T, Error>) -> Void) {
        var request = URLRequest(url: URL(string: "\(baseUrl)/\(endpoint)")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { completion(.failure(error)); return }
            guard let data else { completion(.failure(LicenseAPIError.noData)); return }
            do {
                let decoded = try JSONDecoder().decode(T.self, from: data)
                completion(.success(decoded))
            } catch {
                let bodyString = String(data: data, encoding: .utf8) ?? "<non-UTF8 data, \(data.count) bytes>"
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                Logger.error { "alt-tab-backend \(endpoint) failed: decodingError=\(error), statusCode=\(statusCode.map(String.init) ?? "nil"), body=\(bodyString)" }
                let debugInfo = "statusCode=\(statusCode.map(String.init) ?? "nil"), body=\(bodyString)"
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMessage = json["error"] as? String {
                    completion(.failure(LicenseAPIError.apiError(errorMessage)))
                } else {
                    completion(.failure(LicenseAPIError.invalidResponse(debugInfo: debugInfo)))
                }
            }
        }.resume()
    }

    // MARK: - Response DTOs

    private struct ActivateResponse: Decodable {
        let activated: Bool
        let instance_id: String?
        let variant_id: String?
        let customer_email: String?
        let error: String?
        let instances: [InstanceDTO]?
    }

    private struct ValidateResponse: Decodable {
        let valid: Bool
        let variant_id: String?
    }

    private struct DeactivateResponse: Decodable {
        let deactivated: Bool
        let error: String?
    }

    fileprivate struct InstanceDTO: Decodable {
        let id: String
        let machineName: String?
        let lastSeenAt: Int

        var asActiveInstance: ActiveInstance {
            ActiveInstance(id: id, machineName: machineName, lastSeenAt: Date(timeIntervalSince1970: TimeInterval(lastSeenAt)))
        }
    }
}
