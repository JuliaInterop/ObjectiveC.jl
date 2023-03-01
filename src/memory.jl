# Manual Retain Release

export release, retain

release(obj) = @objc [obj::id release]::Cvoid

retain(obj) = @objc [obj::id retain]::Cvoid
