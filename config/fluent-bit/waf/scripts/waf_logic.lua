-- Logic to classify ModSecurity logs into BLOCKED, SUSPICIOUS, or ALLOWED
function determine_waf_status(tag, timestamp, record)
    -- 1. Initialize variables
    local status = "ALLOWED"
    local http_code = 0
    local messages = record["messages"]
    
    -- 2. Extract HTTP Code safely (handles Integer or String)
    if record["http_code"] then
        http_code = tonumber(record["http_code"])
    end

    -- 3. Check if we have any security alerts in the 'messages' list
    local has_alerts = false
    if messages and type(messages) == "table" and #messages > 0 then
        has_alerts = true
    end

    -- 4. Classification Logic
    if http_code == 403 then
        -- If ModSec returned 403, it explicitly blocked the request.
        status = "BLOCKED"
    elseif has_alerts then
        -- If not blocked (e.g. 200 OK) but alerts exist, it is Suspicious.
        -- This happens in "DetectionOnly" mode or for low-severity rules.
        status = "SUSPICIOUS"
    else
        -- No alerts and not 403 means traffic is clean.
        status = "ALLOWED"
    end

    -- 5. Inject the status into the record
    record["status"] = status

    -- Return 2: Timestamp unchanged, Record modified
    return 2, timestamp, record
end
