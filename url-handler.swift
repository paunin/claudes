#!/usr/bin/env swift
// Read or set the default application for a URL scheme.
//
//   url-handler.swift show <scheme>
//   url-handler.swift set  <scheme> <app path>
//
// macOS keeps one default handler per scheme for the whole login session, so
// this is a switch, not a per-app setting. Every Claude clone inherits the
// `claude` scheme from the original bundle, which is why they compete for it.
import AppKit

let args = CommandLine.arguments
func usage() -> Never {
  FileHandle.standardError.write("usage: url-handler.swift show <scheme> | set <scheme> <app path>\n".data(using: .utf8)!)
  exit(2)
}
guard args.count >= 3 else { usage() }
let mode = args[1], scheme = args[2]
let probe = URL(string: "\(scheme)://x")!
let ws = NSWorkspace.shared

switch mode {
case "show":
  print(ws.urlForApplication(toOpen: probe)?.path ?? "(none)")

case "list":
  let all = (LSCopyApplicationURLsForURL(probe as CFURL, .all)?.takeRetainedValue() as? [URL]) ?? []
  for a in all { print(a.path) }

case "set":
  guard args.count >= 4 else { usage() }
  let app = URL(fileURLWithPath: args[3])
  let sem = DispatchSemaphore(value: 0)
  var failure: Error?
  ws.setDefaultApplication(at: app, toOpenURLsWithScheme: scheme) { error in
    failure = error; sem.signal()
  }
  if sem.wait(timeout: .now() + 10) == .timedOut {
    FileHandle.standardError.write("timed out asking LaunchServices to switch handler\n".data(using: .utf8)!)
    exit(1)
  }
  if let failure {
    FileHandle.standardError.write("\(failure.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
  }
  print(ws.urlForApplication(toOpen: probe)?.path ?? "(none)")

default: usage()
}
