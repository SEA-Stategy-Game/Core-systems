extends RefCounted
class_name DeterminismHash

static func _normalize(value: Variant) -> Variant:
    match typeof(value):
        TYPE_DICTIONARY:
            var dict: Dictionary = value
            var keys: Array = dict.keys()
            keys.sort()
            var out: Dictionary = {}
            for key in keys:
                out[str(key)] = _normalize(dict[key])
            return out
        TYPE_ARRAY:
            var out_arr: Array = []
            for item in value:
                out_arr.append(_normalize(item))
            return out_arr
        TYPE_VECTOR2:
            return {"x": snappedf(value.x, 0.01), "y": snappedf(value.y, 0.01)}
        TYPE_VECTOR2I:
            return {"x": value.x, "y": value.y}
        TYPE_FLOAT:
            return snappedf(value, 0.01)
        TYPE_INT, TYPE_BOOL, TYPE_STRING:
            return value
        _:
            return str(value)

static func canonical_json(value: Variant) -> String:
    return JSON.stringify(_normalize(value))

static func sha256_hex(text: String) -> String:
    var ctx := HashingContext.new()
    var err := ctx.start(HashingContext.HASH_SHA256)
    if err != OK:
        push_error("DeterminismHash: failed to start SHA256 context.")
        return ""
    ctx.update(text.to_utf8_buffer())
    return ctx.finish().hex_encode()

static func snapshot_signature(snapshot: Dictionary) -> String:
    var copy := snapshot.duplicate(true)
    copy.erase("timestamp")
    copy.erase("scenario")
    copy.erase("state_signature")
    return sha256_hex(canonical_json(copy))

static func signature_from_snapshot(snapshot: Dictionary) -> String:
    return snapshot_signature(snapshot)