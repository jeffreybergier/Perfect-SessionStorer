//
//  OffTheShelf.swift
//  SwiftRoom
//
//  Created by Jeffrey Bergier on 10/28/16.
//
//

import PerfectHTTP

public final class SessionStorerNILDelegate<E>: SessionStorerDelegate {
    public typealias K = E
    public func willStore(value: K?, forKey key: String, withToken token: String, on response: HTTPResponse?, storer: SessionStorer<K, SessionStorerNILDelegate>) -> K? { return .none }
    public func shouldReturn(value: K?, forKey key: String, withToken token: String, for request: HTTPRequest, storer: SessionStorer<K, SessionStorerNILDelegate>) -> Bool { return true }
    public func willReturn(value: K?, forKey key: String, withToken token: String, for request: HTTPRequest, storer: SessionStorer<K, SessionStorerNILDelegate>) -> K? { return .none }
    public func didReturn(value: K?, forKey key: String, withToken token: String, for request: HTTPRequest, storer: SessionStorer<K, SessionStorerNILDelegate>) { }
    public func deleted(expired values: [String : K], withToken token: String, storer: SessionStorer<K, SessionStorerNILDelegate>) {}
}

public struct SessionStringStorer {
    public static let shared = SessionStorer<String, SessionStorerNILDelegate<String>>()
}

public struct SessionAnyStorer {
    public static let shared = SessionStorer<Any, SessionStorerNILDelegate<Any>>()
}
