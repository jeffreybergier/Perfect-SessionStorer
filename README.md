# Perfect-SessionStorer
Perfect Session Storer is a really easy to use data storage solution for your Perfect based Swift web app. Session Storer is type safe and can be indexed just like a dictionary.

# Overview
Session Storer uses Swift Generics and standard Cocoa programming patterns. There is the main SessionStorer class and it has a required Data Source and an optional delegate.

* `SessionStorer<T>`
    - This is the primary class. Instantiate this to hold data of any type.
* `SessionStorerDataSource<T>` (required)
    - Subclass this and use it to hook the SessionStorer up to some sort of Database or other storage solution.
    - SessionStorerInMemoryDataSource - A built in Data Source that stores the data in memory.
* `SessionStorerDelegate<T>` (optional) 
    - Subclass this to get in-between saving and retrieving data.
    - One reason to do this is to encrypt / decrypt data between your server code and the data being stored in the data source.

* The last two items should really be protocols. But because of the complexities of Generics when used with protocols, it was much simpler to implement and to use with abstract super classes. When swift supports generic protocols, I will switch over to that.

# Getting Started - The Easy Way

1. Add the dependency to your `Package.swift` file
    - `.Package(url: "https://github.com/jeffreybergier/Perfect-SessionStorer.git", majorVersion: 0, minor: 0)`
1. Choose whether you want to use the String or Any Singletons (you can use both if you want as well)
1. Add the correct filter to the Perfect HTTP Server in the same file that you add your routes
    - ```server.setRequestFilters([(SessionInMemoryStringStorer.shared.filter, .low)])```
1. Store data in the Storer in the function handler for any route.
    - ```SessionInMemoryStringStorer.shared[request, "Username"] = "ToyFanBoi99"```
1. Retrieve data from another request from the same browser
    - ```let username = SessionInMemoryStringStorer.shared[request, "Username"] //optional("ToyFanBoi99")```
    
The singletons provided store data in memory. There is no persistence of this data. So if the server gets killed or crashes, all the data is lost. I hope to be able to provide a SQLite Data Store soon. Also, the default cookie length is 1 year. Data is automatically cleared out by the SessionStorer after it expires.

``` swift
import PerfectSessionStorer

// Register the SessionStorer Filter with the servers request filters
server.setRequestFilters([(SessionInMemoryStringStorer.shared.filter, .low)])

routes.add(method: .get, uri: "/") { request, response in
    // Read out of the SessionStorer
    let username = SessionInMemoryStringStorer.shared[request, "username"] ?? "USER_NOT_LOGGED_IN"
    //...
}
routes.add(method: .get, uri: "/login") { request, response in
    // Save into the SessionStorer
    SessionInMemoryStringStorer.shared[request, "username"] = request.param(name: "username")
    //...
}

```
