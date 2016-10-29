//
//  OffTheShelf.swift
//  SwiftRoom
//
//  Created by Jeffrey Bergier on 10/28/16.
//
//

import PerfectHTTP

// MARK: In Memory Data Source

// This data source is a good one to use if you only need to store things in memory
// If there server stops, no information is persisted

open class SessionStorerInMemoryDataSource<E>: SessionStorerDataSource<E> {
    private var storage = [String : Expire<[String : E]>]()
    open override subscript(storer: SessionStorer<E>, key: String) -> Expire<[String : E]>? {
        get {
            return self.storage[key]
        }
        set {
            self.storage[key] = newValue
        }
    }
    open override func expiredItems(storer: SessionStorer<E>) -> [(key: String,  value: Expire<[String : E]>)] {
        return self.storage.filter({ $0.value.isExpired })
    }
}

// MARK: Singletons for Common Use Cases

// These are easy to use singletons for storing data without having to subclass anything
// The data source is an In Memory data source
// You can create your own and switch it out on the singleton instance.

public struct SessionInMemoryStringStorer {
    private static let dataSource = SessionStorerInMemoryDataSource<String>()
    public static let shared: SessionStorer<String> = {
        let storer = SessionStorer<String>()
        storer.dataSource = dataSource
        return storer
    }()
}

public struct SessionInMemoryAnyStorer {
    private static let dataSource = SessionStorerInMemoryDataSource<Any>()
    public static let shared: SessionStorer<Any> = {
        let storer = SessionStorer<Any>()
        storer.dataSource = dataSource
        return storer
    }()
}
