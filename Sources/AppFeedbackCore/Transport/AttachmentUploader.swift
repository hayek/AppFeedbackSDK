import Foundation

/// Owns the side-effecting GitHub calls that get attachment bytes into the
/// `feedback-attachments` branch and return a stable raw URL. Used by
/// ``GitHubDirectTransport`` during the upload phase of a submission.
struct AttachmentUploader {
    let owner: String
    let repo: String
    let token: String
    let session: URLSession
    let branchName = "feedback-attachments"

    init(owner: String, repo: String, token: String, session: URLSession) {
        self.owner = owner
        self.repo = repo
        self.token = token
        self.session = session
    }

    func ensureBranchExists() async throws {
        // 1. Check branch
        let branchURL = api("/repos/\(percent(owner))/\(percent(repo))/branches/\(branchName)")
        let (_, branchResp) = try await get(branchURL)
        if (branchResp as? HTTPURLResponse)?.statusCode == 200 { return }
        guard (branchResp as? HTTPURLResponse)?.statusCode == 404 else {
            throw URLError(.badServerResponse)
        }

        // 2. Get default branch
        let repoURL = api("/repos/\(percent(owner))/\(percent(repo))")
        let (repoData, _) = try await get(repoURL)
        struct RepoInfo: Decodable { let default_branch: String }
        let defaultBranch = try JSONDecoder().decode(RepoInfo.self, from: repoData).default_branch

        // 3. Get ref SHA
        let refURL = api("/repos/\(percent(owner))/\(percent(repo))/git/refs/heads/\(percent(defaultBranch))")
        let (refData, _) = try await get(refURL)
        struct RefResponse: Decodable { struct Obj: Decodable { let sha: String }; let object: Obj }
        let sha = try JSONDecoder().decode(RefResponse.self, from: refData).object.sha

        // 4. Create branch
        let createURL = api("/repos/\(percent(owner))/\(percent(repo))/git/refs")
        let payload: [String: String] = [
            "ref": "refs/heads/\(branchName)",
            "sha": sha,
        ]
        try await post(createURL, json: payload, expecting: 201)
    }

    // MARK: - HTTP helpers

    private func api(_ path: String) -> URL {
        URL(string: "https://api.github.com\(path)")!
    }
    private func percent(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }

    private func get(_ url: URL) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return try await session.data(for: req)
    }

    private func post<T: Encodable>(_ url: URL, json: T, expecting expectedStatus: Int) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.httpBody = try JSONEncoder().encode(json)
        let (_, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == expectedStatus else {
            throw URLError(.badServerResponse)
        }
    }
}
