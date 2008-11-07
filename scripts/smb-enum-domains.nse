description = [[
Attempts to enumerate domains on a system, along with their policies. This will likely only work without credentials against Windows 2000. 

After the initial <code>bind()</code> to SAMR, the sequence of calls is:
* <code>Connect4()</code>: get a connect_handle
* <code>EnumDomains()</code>: get a list of the domains (stop here if you just want the names).
* <code>QueryDomain()</code>: get the SID for the domain.
* <code>OpenDomain()</code>: get a handle for each domain.
* <code>QueryDomainInfo2()</code>: get the domain information.
* <code>QueryDomainUsers()</code>: get a list of the users in the domain.
]]

---
--@usage
-- nmap --script smb-enumdomains.nse -p445 <host>
-- sudo nmap -sU -sS --script smb-enumdomains.nse -p U:137,T:139 <host>
--
--@output
-- Host script results:
-- |  smb-enum-domains:
-- |  Domain: LOCALSYSTEM
-- |   |_ SID: S-1-5-21-2956463495-2656032972-1271678565
-- |   |_ Users: Administrator, Guest, SUPPORT_388945a0
-- |   |_ Creation time: 2007-11-26 15:24:04
-- |   |_ Passwords: min length: 11 characters; min age: 5 days; max age: 63 days
-- |   |_ Password lockout: 3 attempts in under 15 minutes will lock the account until manually reset
-- |   |_ Password history : 5 passwords
-- |   |_ Password properties:
-- |     |_  Password complexity requirements exist
-- |     |_  Administrator account cannot be locked out
-- |  Domain: Builtin
-- |   |_ SID: S-1-5-32
-- |   |_ Users:
-- |   |_ Creation time: 2007-11-26 15:24:04
-- |   |_ Passwords: min length: n/a; min age: n/a; max age: 42 days
-- |   |_ Account lockout disabled
-- |   |_ Password properties:
-- |     |_  Password complexity requirements do not exist
-- |_    |_  Administrator account cannot be locked out
-- 
-- @args smb* This script supports the <code>smbusername</code>,
-- <code>smbpassword</code>, <code>smbhash</code>, <code>smbguest</code>, and
-- <code>smbtype</code> script arguments of the <code>smb</code> module.
-----------------------------------------------------------------------

author = "Ron Bowes"
copyright = "Ron Bowes"
license = "Same as Nmap--See http://nmap.org/book/man-legal.html"
categories = {"discovery","intrusive"}

require 'msrpc'
require 'smb'
require 'stdnse'

hostrule = function(host)

	local port = smb.get_port(host)

	if(port == nil) then
		return false
	else
		return true
	end

end

action = function(host)
	local response = " \n"
	local status, smbstate

	-- Create the SMB session
	status, smbstate  = msrpc.start_smb(host, msrpc.SAMR_PATH)
	if(status == false) then
		if(nmap.debugging() > 0) then
			return "ERROR: " .. smbstate
		else
			return nil
		end
	end

	-- Bind to SAMR service
	status, bind_result = msrpc.bind(smbstate, msrpc.SAMR_UUID, msrpc.SAMR_VERSION, nil)
	if(status == false) then
		msrpc.stop_smb(smbstate)
		if(nmap.debugging() > 0) then
			return "ERROR: " .. bind_result
		else
			return nil
		end
	end

	-- Call connect4()
	status, connect4_result = msrpc.samr_connect4(smbstate, host.ip)
	if(status == false) then
		msrpc.stop_smb(smbstate)
		if(nmap.debugging() > 0) then
			return "ERROR: " .. connect4_result
		else
			return nil
		end
	end

	-- Save the connect_handle
	connect_handle = connect4_result['connect_handle']

	-- Call EnumDomains()
	status, enumdomains_result = msrpc.samr_enumdomains(smbstate, connect_handle)
	if(status == false) then
		msrpc.stop_smb(smbstate)
		if(nmap.debugging() > 0) then
			return "ERROR: " .. enumdomains_result
		else
			return nil
		end
	end

	-- If no domains were returned, print an error (I don't expect this will actually happen)
	if(#enumdomains_result['domains'] == 0) then
		if(nmap.debugging() > 0) then
			return "ERROR: Couldn't find any domains to check"
		else
			return nil
		end
	end

	for i = 1, #enumdomains_result['domains'], 1 do

		local domain = enumdomains_result['domains'][i]
		local sid
		local domain_handle

		-- Call LookupDomain()
		status, lookupdomain_result = msrpc.samr_lookupdomain(smbstate, connect_handle, domain)
		if(status == false) then
			msrpc.stop_smb(smbstate)
			if(nmap.debugging() > 0) then
				return "ERROR: " .. lookupdomain_result
			else
				return nil
			end
		end

		-- Save the sid
		sid = lookupdomain_result['sid']

		-- Call OpenDomain()
		status, opendomain_result = msrpc.samr_opendomain(smbstate, connect_handle, sid)
		if(status == false) then
			msrpc.stop_smb(smbstate)
			if(nmap.debugging() > 0) then
				return "ERROR: " .. opendomain_result
			else
				return nil
			end
		end

		-- Save the domain handle
		domain_handle = opendomain_result['domain_handle']

		-- Call QueryDomainInfo2() to get domain properties. We call these for three types == 1, 8, and 12, since those return
		-- the most useful information. 
		status, querydomaininfo2_result = msrpc.samr_querydomaininfo2(smbstate, domain_handle, 1)
		if(status == false) then
			msrpc.stop_smb(smbstate)
			if(nmap.debugging() > 0) then
				return "ERROR: " .. querydomaininfo2_result
			else
				return nil
			end
		end

		status, querydomaininfo2_result = msrpc.samr_querydomaininfo2(smbstate, domain_handle, 8, querydomaininfo2_result)
		if(status == false) then
			msrpc.stop_smb(smbstate)
			if(nmap.debugging() > 0) then
				return "ERROR: " .. querydomaininfo2_result
			else
				return nil
			end
		end

		status, querydomaininfo2_result = msrpc.samr_querydomaininfo2(smbstate, domain_handle, 12, querydomaininfo2_result)
		if(status == false) then
			msrpc.stop_smb(smbstate)
			if(nmap.debugging() > 0) then
				return "ERROR: " .. querydomaininfo2_result
			else
				return nil
			end
		end

		-- Call EnumDomainUsers() to get users
		status, enumdomainusers_result = msrpc.samr_enumdomainusers(smbstate, domain_handle)
		if(status == false) then
			msrpc.stop_smb(smbstate)
			if(nmap.debugging() > 0) then
				return "ERROR: " .. enumdomainusers_result
			else
				return nil
			end
		end

		-- Close the domain handle
		msrpc.samr_close(smbstate, domain_handle)

		-- Finally, fill in the response!
		response = response .. string.format("Domain: %s\n", domain)
		response = response .. string.format(" |_ SID: %s\n",                               msrpc.sid_to_string(lookupdomain_result['sid']))
		response = response .. string.format(" |_ Users: %s\n",                             stdnse.strjoin(", ", enumdomainusers_result['names']))
		response = response .. string.format(" |_ Creation time: %s\n",                     querydomaininfo2_result['create_date'])

		-- Password characteristics
		local min_password_length = querydomaininfo2_result['min_password_length']
		local max_password_age = querydomaininfo2_result['max_password_age']
		local min_password_age = querydomaininfo2_result['min_password_age']

		if(min_password_length > 0) then
			min_password_length = string.format("%d characters", min_password_length)
		else
			min_password_length = "n/a"
		end

		if(max_password_age > 0 and max_password_age < 5000) then
			max_password_age = string.format("%d days", max_password_age)
		else
			max_password_age = "n/a"
		end

		if(min_password_age > 0) then
			min_password_age = string.format("%d days", min_password_age)
		else
			min_password_age = "n/a"
		end

		response = response .. string.format(" |_ Passwords: min length: %s; min age: %s; max age: %s\n", min_password_length, min_password_age, max_password_age)

		local lockout_duration = querydomaininfo2_result['lockout_duration']
		if(lockout_duration < 0) then
			lockout_duration = string.format("for %d minutes", querydomaininfo2_result['lockout_duration'])
		else
			lockout_duration = "until manually reset"
		end

		if(querydomaininfo2_result['lockout_threshold'] > 0) then
			response = response .. string.format(" |_ Password lockout: %d attempts in under %d minutes will lock the account %s\n",  querydomaininfo2_result['lockout_threshold'], querydomaininfo2_result['lockout_window'], lockout_duration)
		else
			response = response .. string.format(" |_ Account lockout disabled\n")
		end

		if(querydomaininfo2_result['password_history_length']) > 0 then
			response = response .. string.format(" |_ Password history : %d passwords\n", querydomaininfo2_result['password_history_length'])
		end

		if(#querydomaininfo2_result['password_properties_list'] > 0) then
			response = response .. " |_ Password properties: \n   |_  " .. stdnse.strjoin("\n   |_  ", querydomaininfo2_result['password_properties_list']) .. "\n"
		end
	end

	-- Close the connect handle
	msrpc.samr_close(smbstate, connect_handle)

	-- Close the SMB session
	msrpc.stop_smb(smbstate)

	return response

end

