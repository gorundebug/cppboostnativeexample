#!/usr/bin/env python3

import json
import sys
import urllib.request


def get(path: str) -> tuple[int, str]:
    with urllib.request.urlopen(f"http://localhost:{path}", timeout=5) as response:
        return response.status, response.read().decode()


def process(request_id: str, items: list[dict]) -> dict:
    request = urllib.request.Request(
        "http://localhost:9091/v1/processorder",
        data=json.dumps({"items": items}).encode(),
        headers={"Content-Type": "application/json", "X-Request-ID": request_id},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        assert response.status == 200
        return json.loads(response.read())


def main() -> None:
    assert get("9091/status/data") == (200, '{"status":"ok"}')
    assert get("9092/status/data") == (200, '{"status":"ok"}')
    confirmed = process(
        "native-confirmed",
        [{"item_id": "item-1", "sku": "SKU-001", "quantity": 2, "unit_price": 10.5}],
    )
    assert confirmed["order_id"] == "native-confirmed"
    assert confirmed["status"] == "CONFIRMED"
    assert confirmed["total_amount"] == 21
    assert confirmed["confirmed_items"] == [{
        "item_id": "item-1", "sku": "SKU-001", "available_qty": 2,
        "reserved": True, "status": "CONFIRMED",
    }]
    out_of_stock = process(
        "native-out-of-stock",
        [{"item_id": "item-x", "sku": "UNKNOWN", "quantity": 1, "unit_price": 3}],
    )
    assert out_of_stock["status"] == "PARTIALLY_CONFIRMED"
    assert out_of_stock["confirmed_items"][0]["status"] == "OUT_OF_STOCK"
    assert out_of_stock["confirmed_items"][0]["reserved"] is False
    print("cppboostnativeexample integration: PASS")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"cppboostnativeexample integration: FAIL: {error}", file=sys.stderr)
        raise
