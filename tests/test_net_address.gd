extends GdUnitTestSuite
## Plan 04-03 Task 2: NetAddress classifier and invite ordering (D-15, NET-07, UI-SPEC 8.1).


func test_classify_tailscale() -> void:
	assert_str(NetAddress.classify("100.101.5.7")).is_equal("tailscale")
	assert_str(NetAddress.classify("100.64.0.1")).is_equal("tailscale")
	assert_str(NetAddress.classify("100.127.255.254")).is_equal("tailscale")
	assert_str(NetAddress.classify("100.128.0.1")).is_equal("other")
	assert_str(NetAddress.classify("100.63.0.1")).is_equal("other")


func test_classify_lan() -> void:
	assert_str(NetAddress.classify("192.168.1.4")).is_equal("lan")
	assert_str(NetAddress.classify("10.0.0.2")).is_equal("lan")
	assert_str(NetAddress.classify("172.20.1.1")).is_equal("lan")
	assert_str(NetAddress.classify("172.16.0.1")).is_equal("lan")
	assert_str(NetAddress.classify("172.31.255.1")).is_equal("lan")
	assert_str(NetAddress.classify("172.32.0.1")).is_equal("other")


func test_classify_hidden() -> void:
	for ip in ["127.0.0.1", "::1", "169.254.3.3", "fe80::1", "fe80::1%12", "0.0.0.0", "", "nope",
			"1.2.3", "300.1.1.1", "::"]:
		assert_str(NetAddress.classify(ip)).override_failure_message(ip).is_equal("")


func test_classify_other() -> void:
	assert_str(NetAddress.classify("8.8.8.8")).is_equal("other")
	assert_str(NetAddress.classify("2001:db8::5")).is_equal("other")


func test_display_list_order_and_cap() -> void:
	var addrs := PackedStringArray(["127.0.0.1", "8.8.8.8", "192.168.1.4", "fe80::1", "10.0.0.2",
			"100.101.5.7", "169.254.3.3", "2001:db8::5", "100.64.0.9"])
	var list := NetAddress.display_list(addrs)
	assert_int(list.size()).is_equal(4)
	assert_str(list[0].ip).is_equal("100.101.5.7")
	assert_str(list[0].kind).is_equal("tailscale")
	assert_str(list[1].ip).is_equal("100.64.0.9")
	assert_str(list[2].ip).is_equal("192.168.1.4")
	assert_str(list[2].kind).is_equal("lan")
	assert_str(list[3].ip).is_equal("10.0.0.2")


func test_display_list_dedup_and_empty() -> void:
	var list := NetAddress.display_list(PackedStringArray(["10.0.0.2", "10.0.0.2", "127.0.0.1"]))
	assert_int(list.size()).is_equal(1)
	assert_int(NetAddress.display_list(PackedStringArray()).size()).is_equal(0)


func test_invite_address() -> void:
	assert_str(NetAddress.invite_address(PackedStringArray(["192.168.1.4", "100.101.5.7"]))).is_equal("100.101.5.7")
	assert_str(NetAddress.invite_address(PackedStringArray(["8.8.8.8", "192.168.1.4"]))).is_equal("192.168.1.4")
	assert_str(NetAddress.invite_address(PackedStringArray(["8.8.8.8", "127.0.0.1"]))).is_equal("")
	assert_str(NetAddress.invite_address(PackedStringArray())).is_equal("")


func test_host_port_brackets_ipv6() -> void:
	assert_str(NetAddress.host_port("100.101.5.7", 47474)).is_equal("100.101.5.7:47474")
	assert_str(NetAddress.host_port("2001:db8::5", 47474)).is_equal("[2001:db8::5]:47474")
	assert_str(NetAddress.host_port("[2001:db8::5]", 1)).is_equal("[2001:db8::5]:1")
