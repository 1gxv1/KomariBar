import SwiftUI

// Explicitly use the long-standing property wrapper on every supported SDK.
// Newer SDKs also export a State macro whose plugin is absent in some CLT installs.
typealias LocalState<Value> = SwiftUI.State<Value>
