"""Gera as coleções do Postman em postman/ a partir das specs OpenAPI publicadas.

Uso: python3 scripts/postman/build.py (precisa de Node para o npx).
"""
import json, os, subprocess, tempfile, uuid

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "postman")
SPECS = "https://app.deliveryvip.com.br/swaggers/{}.yaml"
WORK = tempfile.mkdtemp()


def load(name):
    spec = os.path.join(WORK, f"{name}.yaml")
    raw = os.path.join(WORK, f"{name}.json")
    if not os.path.exists(raw):
        subprocess.run(["curl", "-sSfL", "-o", spec, SPECS.format(name)], check=True)
        subprocess.run(
            ["npx", "--yes", "openapi-to-postmanv2@4.25.0", "-s", spec, "-o", raw, "-p",
             "-O", "folderStrategy=Tags"],
            check=True, stdout=subprocess.DEVNULL)
    return json.load(open(raw))
FOLDERS = {
    "Events": "Eventos", "Orders": "Pedidos", "Discounts": "Descontos", "Tabs": "Comandas",
    "Places": "Mesas", "Utils": "Ferramentas", "Merchants": "Lojas", "Loyalty": "Fidelidade",
    "OAuth": "Autenticação", "Versions": "Versões", "Authentication": "Autenticação",
    "Resales": "Revendas", "Partners": "Parceiro", "Members": "Membros", "Subscriptions": "Assinaturas",
    "Features": "Recursos", "Invoices": "Faturas", "Applications": "Aplicações", "Plans": "Planos",
    "Signup": "Cadastro", "Webhooks": "Webhooks",
}
ID_VARS = ["merchantId", "orderId", "partnerId", "resaleId", "discountId", "tabId", "placeId", "memberId", "planId", "applicationId"]
seen_folders = set()


def walk(items):
    out = []
    for it in items:
        if "item" in it:
            if not it["item"]:
                continue
            seen_folders.add(it["name"])
            it["name"] = "/".join(FOLDERS.get(part, part) for part in it["name"].split("/"))
            it["item"] = walk(it["item"])
            it.pop("auth", None)
        else:
            req = it["request"]
            for v in req["url"].get("variable", []):
                if v.get("key") in ID_VARS:
                    v["value"] = "{{%s}}" % v["key"]
            req.pop("auth", None)
            path = "/".join(req["url"]["path"])
            if path.endswith(("oauth/token", "oauth/revoke", "oauth/introspect")):
                req["auth"] = {"type": "noauth"}
        out.append(it)
    return out

def oauth(token_url):
    return {
        "type": "oauth2",
        "oauth2": [
            {"key": "grant_type", "value": "client_credentials", "type": "string"},
            {"key": "accessTokenUrl", "value": token_url, "type": "string"},
            {"key": "clientId", "value": "{{clientId}}", "type": "string"},
            {"key": "clientSecret", "value": "{{clientSecret}}", "type": "string"},
            {"key": "scope", "value": "{{scope}}", "type": "string"},
            {"key": "client_authentication", "value": "body", "type": "string"},
            {"key": "tokenName", "value": "DeliveryVip", "type": "string"},
            {"key": "addTokenTo", "value": "header", "type": "string"},
        ],
    }

def build(name, title, description, base_url, scope, token_url, parts, filename):
    items = []
    for part in parts:
        c = load(part)
        items += walk(c["item"])
    # one folder per name: merge duplicates (e.g. Autenticação)
    merged, index = [], {}
    for it in items:
        if "item" in it and "/" in it["name"]:
            parent, child = it["name"].split("/", 1)
            it["name"] = child
            index[parent]["item"].append(it)
        elif "item" in it and it["name"] in index:
            index[it["name"]]["item"] += it["item"]
        else:
            if "item" in it:
                index[it["name"]] = it
            merged.append(it)
    col = {
        "info": {
            "_postman_id": str(uuid.uuid5(uuid.NAMESPACE_URL, "deliveryvip/" + filename)),
            "name": title,
            "description": description,
            "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json",
        },
        "auth": oauth(token_url),
        "variable": [
            {"key": "baseUrl", "value": base_url},
            {"key": "scope", "value": scope},
        ],
        "item": merged,
    }
    json.dump(col, open(os.path.join(OUT, filename), "w"), ensure_ascii=False, indent=2)
    n = sum(1 for _ in iter_requests(merged))
    print(filename, n, "requisições")

def iter_requests(items):
    for it in items:
        if "item" in it:
            yield from iter_requests(it["item"])
        else:
            yield it

DOCS = "Dúvidas: https://discord.gg/AJF8Yha4"
build(
    "merchant", "DeliveryVip — Merchant API V3",
    "Pedidos, eventos, catálogo, descontos, comandas, mesas e fidelidade da Merchant API V3.\n\n"
    "Preencha clientId, clientSecret e merchantId no ambiente **DeliveryVip**, abra a aba Authorization da coleção e clique em **Get New Access Token**.\n\n" + DOCS,
    "https://api.deliveryvip.com.br", "od.all",
    "https://api.deliveryvip.com.br/authentication/v1/oauth/token",
    ["authentication", "merchant"], "deliveryvip-merchant-api.postman_collection.json")
build(
    "partner", "DeliveryVip — Partner API V2",
    "Lojas, revendas, membros, assinaturas, recursos e faturas da Partner API V2.\n\n"
    "Preencha clientId, clientSecret e partnerId no ambiente **DeliveryVip**, abra a aba Authorization da coleção e clique em **Get New Access Token**.\n\n" + DOCS,
    "https://api.deliveryvip.com.br", "dv.partner",
    "https://api.deliveryvip.com.br/authentication/v1/oauth/token",
    ["authentication", "partner"], "deliveryvip-partner-api.postman_collection.json")
build(
    "opendelivery", "DeliveryVip — Open Delivery",
    "Rotas Open Delivery da DeliveryVip como Ordering Application.\n\n"
    "Use o client_id do app e o client_secret da loja no ambiente **DeliveryVip**, abra a aba Authorization da coleção e clique em **Get New Access Token**.\n\n" + DOCS,
    "https://od.deliveryvip.com.br", "od.all",
    "https://od.deliveryvip.com.br/oauth/token",
    ["opendelivery"], "deliveryvip-open-delivery.postman_collection.json")

env = {
    "id": str(uuid.uuid5(uuid.NAMESPACE_URL, "deliveryvip/env")),
    "name": "DeliveryVip",
    "values": [
        {"key": "clientId", "value": "", "type": "default", "enabled": True},
        {"key": "clientSecret", "value": "", "type": "secret", "enabled": True},
        {"key": "merchantId", "value": "", "type": "default", "enabled": True},
        {"key": "partnerId", "value": "", "type": "default", "enabled": True},
        {"key": "orderId", "value": "", "type": "default", "enabled": True},
    ],
    "_postman_variable_scope": "environment",
}
json.dump(env, open(os.path.join(OUT, "deliveryvip.postman_environment.json"), "w"), ensure_ascii=False, indent=2)
