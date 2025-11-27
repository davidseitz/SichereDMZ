function parse_nftables(tag, timestamp, record)
    local raw_log = record["log"]
    if raw_log == nil then return 0, timestamp, record end

    local new_record = {}
    
    -- 1. SPLIT BY COMMA (Parse KV pairs)
    -- Iterate through every chunk separated by comma
    for pair in string.gmatch(raw_log, "([^,]+)") do
        -- Split by first equals sign
        local key, val = string.match(pair, "^%s*([^=]+)=(.+)")
        if key and val then
            -- Trim spaces
            key = key:match("^%s*(.-)%s*$")
            val = val:match("^%s*(.-)%s*$")
            new_record[key] = val
        end
    end

    -- 2. NORMALIZE PREFIX (Rule Name)
    if new_record["oob.prefix"] then
        -- Remove trailing colon and space (e.g., "FWI...: " -> "FWI...")
        new_record["rule_name"] = new_record["oob.prefix"]:gsub(":%s*$", "")
        
        -- Try to detect Action (ALLOW/DROP) from the name
        if string.find(new_record["rule_name"], "ALLOW") then
            new_record["action"] = "ALLOW"
        elseif string.find(new_record["rule_name"], "DROP") then
            new_record["action"] = "DROP"
        elseif string.find(new_record["rule_name"], "REJECT") then
            new_record["action"] = "REJECT"
        else
            new_record["action"] = "UNKNOWN"
        end
    end

    -- 3. NORMALIZE PROTOCOL
    local proto_num = tonumber(new_record["ip.protocol"])
    if proto_num == 6 then
        new_record["protocol"] = "TCP"
    elseif proto_num == 17 then
        new_record["protocol"] = "UDP"
    elseif proto_num == 1 then
        new_record["protocol"] = "ICMP"
    else
        new_record["protocol"] = tostring(proto_num)
    end

    -- 4. NORMALIZE PORTS
    -- Merge tcp.dport and udp.dport into one field
    if new_record["tcp.dport"] then
        new_record["dest_port"] = tonumber(new_record["tcp.dport"])
        new_record["src_port"]  = tonumber(new_record["tcp.sport"])
    elseif new_record["udp.dport"] then
        new_record["dest_port"] = tonumber(new_record["udp.dport"])
        new_record["src_port"]  = tonumber(new_record["udp.sport"])
    end

    -- 5. FIX TIMESTAMP
    -- Use the log's internal timestamp (oob.time.sec) instead of read time
    local new_time = timestamp
    if new_record["oob.time.sec"] then
        new_time = tonumber(new_record["oob.time.sec"])
    end

    -- Return 2 = Replace record, Update timestamp
    return 2, new_time, new_record
end
