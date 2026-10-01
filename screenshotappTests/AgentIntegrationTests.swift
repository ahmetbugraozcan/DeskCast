import Foundation
import Testing
@testable import screenshotapp

struct IntegrationParserTests {
    private func data(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    @Test func stripe() throws {
        let balance = try data([
            "available": [["amount": 1_000, "currency": "eur"]],
            "pending": [["amount": 250, "currency": "eur"], ["amount": 99, "currency": "usd"]]
        ])
        let total = try #require(IntegrationParsers.stripeBalance(balance))
        #expect(total.amount == 1_250)
        #expect(total.currency == "eur")

        let charges = try data(["data": [
            ["id": "ch_1", "amount": 4_900, "currency": "eur", "status": "succeeded", "created": 1_700_000_000, "description": "Pro plan"],
            ["id": "ch_2", "amount": 100, "currency": "eur", "status": "failed", "created": 1_700_000_100,
             "billing_details": ["name": "Ada"]]
        ]])
        let payments = IntegrationParsers.stripePayments(charges)
        #expect(payments.map(\.summary) == ["Pro plan", "Ada"])
        #expect(payments.map(\.succeeded) == [true, false])
    }

    @Test func vercelAndN8n() throws {
        let deployments = IntegrationParsers.vercelDeployments(try data(["deployments": [
            ["uid": "d1", "name": "site", "url": "site.vercel.app", "state": "READY", "createdAt": 1_700_000_000_000,
             "meta": ["githubCommitMessage": "Fix hero", "githubCommitRef": "main"]],
            ["uid": "d2", "name": "api", "state": "BUILDING", "createdAt": 1_700_000_100_000]
        ]]))
        #expect(deployments.first?.commit == "Fix hero")
        #expect(deployments.first?.succeeded == true)
        #expect(deployments.last?.isFinished == false)

        let executions = IntegrationParsers.n8nExecutions(try data(["data": [
            ["id": 12, "workflowId": "7", "status": "error", "startedAt": "2026-10-01T10:00:00.000Z"],
            ["id": "13", "workflowId": "7", "finished": true]
        ]]))
        #expect(executions.map(\.id) == ["12", "13"])
        #expect(executions.first?.failed == true)
        #expect(executions.last?.status == "success")
        #expect(IntegrationParsers.n8nWorkflowNames(try data(["data": [["id": "7", "name": "Morning brief"]]])) == ["7": "Morning brief"])
    }

    @Test func resendGitHubNotionAndCal() throws {
        let resend = IntegrationParsers.resendEmails(try data(["total": 42, "data": [
            ["id": "e1", "to": ["a@b.com"], "subject": "Hi", "created_at": "2026-10-01 10:00:00.000+00", "last_event": "delivered"]
        ]]))
        #expect(resend.total == 42)
        #expect(resend.emails.first?.recipients == ["a@b.com"])

        let summary = IntegrationParsers.gitHubSummary(
            user: try data(["login": "me", "public_repos": 3, "owned_private_repos": 2, "followers": 9]),
            repositories: try data([["stargazers_count": 5], ["stargazers_count": 7]])
        )
        #expect(summary == GitHubSummary(login: "me", repositories: 5, stars: 12, followers: 9))

        let pages = IntegrationParsers.notionPages(try data(["results": [
            ["id": "p1", "object": "page", "last_edited_time": "2026-10-01T09:00:00.000Z", "url": "https://notion.so/p1",
             "icon": ["type": "emoji", "emoji": "📝"],
             "properties": ["Name": ["type": "title", "title": [["plain_text": "Road"], ["plain_text": "map"]]]]]
        ]]))
        #expect(pages.first?.title == "Roadmap")
        #expect(pages.first?.emoji == "📝")

        let bookings = IntegrationParsers.calBookings(try data(["data": [
            ["id": 2, "title": "Later", "start": "2026-10-03T09:00:00Z"],
            ["id": 1, "title": "Sooner", "start": "2026-10-02T09:00:00Z", "attendees": [["name": "Ada"]]]
        ]]))
        #expect(bookings.map(\.title) == ["Sooner", "Later"])
        #expect(bookings.first?.attendee == "Ada")
    }

    @Test func newsAndFormatting() {
        let snapshot = IntegrationSnapshot.vercel([
            VercelDeployment(id: "a", project: "site", url: "", state: "READY", date: .now, commit: nil, branch: nil),
            VercelDeployment(id: "b", project: "api", url: "", state: "ERROR", date: .now, commit: nil, branch: nil),
            VercelDeployment(id: "c", project: "web", url: "", state: "BUILDING", date: .now, commit: nil, branch: nil)
        ])
        let events = AgentIntegrationsViewModel.finishedEvents(in: snapshot)
        #expect(events.map(\.id) == ["a", "b"])
        #expect(events.map(\.failed) == [false, true])

        let runs = IntegrationSnapshot.n8n([
            N8nExecution(id: "1", workflowID: nil, workflowName: "A", status: "success", date: nil),
            N8nExecution(id: "2", workflowID: nil, workflowName: "B", status: "crashed", date: nil)
        ])
        #expect(AgentIntegrationsViewModel.finishedEvents(in: runs).map(\.id) == ["2"])

        let dollars = IntegrationFormat.money(4_950, currency: "usd")
        #expect(dollars.contains("49.50") || dollars.contains("49,50"))
        #expect(!IntegrationFormat.money(500, currency: "jpy").contains("5.00"))
        #expect(IntegrationClient.normalized(" https://n8n.example.com// ") == "https://n8n.example.com")
        #expect(IntegrationClient.normalized("http://n8n.example.com") == nil)
    }
}
