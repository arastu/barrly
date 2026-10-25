import SwiftUI

/// Drop-in replacement for `@State`. On the macOS 26+ SDK `@State` is a compiler macro whose
/// plugin ships only with Xcode; this wrapper uses the underlying `SwiftUICore.State` storage
/// directly so Barrly builds with the Command Line Tools alone.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
  private var storage: SwiftUICore.State<Value>
  init(wrappedValue: Value) { storage = SwiftUICore.State(wrappedValue: wrappedValue) }
  var wrappedValue: Value {
    get { storage.wrappedValue }
    nonmutating set { storage.wrappedValue = newValue }
  }
  var projectedValue: Binding<Value> { storage.projectedValue }
}
