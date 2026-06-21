import Testing

@testable import SharedModels

@Suite("LanguageDetector")
struct LanguageDetectorTests {

    @Test("Empty and whitespace-only input is Plain Text")
    func emptyIsPlainText() {
        #expect(LanguageDetector.detect("") == .plainText)
        #expect(LanguageDetector.detect("   \n\t  ") == .plainText)
    }

    @Test("Ambiguous prose is Plain Text")
    func proseIsPlainText() {
        let text = """
            Buy milk and eggs on the way home.
            Remember to call the dentist tomorrow morning.
            """
        #expect(LanguageDetector.detect(text) == .plainText)
    }

    @Test("Detects JSON")
    func detectsJSON() {
        let text = #"{ "name": "Snip", "version": 1, "tags": ["a", "b"] }"#
        #expect(LanguageDetector.detect(text) == .json)
    }

    @Test("Malformed JSON-looking text is not JSON")
    func malformedJSONIsNotJSON() {
        // Looks like an object but doesn't parse; should not be reported as JSON.
        #expect(LanguageDetector.detect("{ name: Snip, ") != .json)
    }

    @Test("Detects HTML")
    func detectsHTML() {
        let text = """
            <!DOCTYPE html>
            <html>
              <body>
                <div class="card"><p>Hello</p></div>
              </body>
            </html>
            """
        #expect(LanguageDetector.detect(text) == .html)
    }

    @Test("Detects CSS")
    func detectsCSS() {
        let text = """
            .card {
              color: #ffffff;
              padding: 8px;
              margin: 0 auto;
            }
            @media (max-width: 600px) { .card { padding: 4px; } }
            """
        #expect(LanguageDetector.detect(text) == .css)
    }

    @Test("Detects SQL")
    func detectsSQL() {
        let text = """
            SELECT id, title FROM snippets
            WHERE deleted_at IS NULL
            ORDER BY updated_at DESC;
            """
        #expect(LanguageDetector.detect(text) == .sql)
    }

    @Test("Detects Swift")
    func detectsSwift() {
        let text = """
            import Foundation

            struct Snippet {
                let id: UUID
                func title() -> String {
                    guard !id.uuidString.isEmpty else { return "" }
                    return id.uuidString
                }
            }
            """
        #expect(LanguageDetector.detect(text) == .swift)
    }

    @Test("Detects Python")
    func detectsPython() {
        let text = """
            import os

            def greet(name):
                if name:
                    print(f"Hello {name}")
                else:
                    print("Hello")
            """
        #expect(LanguageDetector.detect(text) == .python)
    }

    @Test("Detects Bash")
    func detectsBash() {
        let text = """
            #!/bin/bash
            for f in *.txt; do
              echo "Processing $f"
            done
            """
        #expect(LanguageDetector.detect(text) == .bash)
    }

    @Test("Detects TypeScript over JavaScript")
    func detectsTypeScript() {
        let text = """
            interface User {
              id: number;
              name: string;
            }

            const greet = (user: User): string => {
              return `Hello ${user.name}`;
            };
            """
        #expect(LanguageDetector.detect(text) == .typescript)
    }

    @Test("Detects JavaScript (no type annotations)")
    func detectsJavaScript() {
        let text = """
            const express = require("express");
            const app = express();

            function handler(req, res) {
              console.log("request");
              res.end("ok");
            }
            module.exports = app;
            """
        #expect(LanguageDetector.detect(text) == .javascript)
    }

    @Test("Detects PHP")
    func detectsPHP() {
        let text = """
            <?php
            $name = "Snip";
            function greet() {
                return $name;
            }
            echo greet();
            """
        #expect(LanguageDetector.detect(text) == .php)
    }

    @Test("Detects GraphQL")
    func detectsGraphQL() {
        let text = """
            type User {
              id: ID!
              name: String!
            }

            type Query {
              user(id: ID!): User
            }
            """
        #expect(LanguageDetector.detect(text) == .graphql)
    }

    @Test("Detects YAML")
    func detectsYAML() {
        let text = """
            name: Snip
            version: 1
            tags:
              - a
              - b
            nested:
              key: value
            """
        #expect(LanguageDetector.detect(text) == .yaml)
    }

    @Test("Detects Markdown")
    func detectsMarkdown() {
        let text = """
            # Title

            Some text with **bold** and a [link](https://example.com).

            - item one
            - item two
            """
        #expect(LanguageDetector.detect(text) == .markdown)
    }
}
