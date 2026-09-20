-- Loaded by the RPM smoke test: assert the bundled limit library is
-- loadable with the runtime's lualib on package.path.
package.path = "/usr/local/openresty/lualib/?.lua;/usr/local/openresty/lualib/?/init.lua;" .. package.path
local ok = pcall(require, "resty.limit.traffic")
assert(ok, "resty.limit.traffic failed to load")
