// Copyright (c) 2026 Paul Butcher. All rights reserved.
// Released under Apache 2.0 license as described in the file LICENSE.

#include <lean/lean.h>
#include <libxml/parser.h>
#include <libxml/tree.h>
#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>
#include <libxml/xmlerror.h>
#include <stdlib.h>
#include <string.h>

// A doc handle always exists once allocated, even when the underlying parse
// failed and `doc` is NULL; this lets the finalizer and the Lean-side
// `docIsNull` check work uniformly instead of needing an `Option` at the FFI
// boundary.
typedef struct {
    xmlDocPtr doc;
} lx_doc;

static void lx_doc_finalize(void *ptr) {
    lx_doc *d = (lx_doc *)ptr;
    if (d->doc) xmlFreeDoc(d->doc);
    free(d);
}

// A doc handle holds no Lean objects, only C-managed memory.
static void lx_doc_foreach(void *mod, b_lean_obj_arg fn) {}

static lean_external_class *g_doc_class = NULL;

// Node, XPath context and XPath object pointers are passed to/from Lean as
// raw addresses boxed in a `USize`, never as their own external-class
// objects. They stay valid only as long as the doc handle that owns the
// underlying tree remains alive, which Lean's GC guarantees as long as the
// handle is reachable from the caller (see README for the full argument).

typedef struct {
    char *message;
    int domain;
    int code;
    int line;
} lx_error;

// Structured errors are collected here by `lx_error_handler`, attached to
// each parser/XPath context as it is created, then drained by the Lean
// side after the call returns. This assumes libxml2 calls are not made
// concurrently from multiple threads.
static lx_error *g_errors = NULL;
static size_t g_errors_len = 0;
static size_t g_errors_cap = 0;

static void lx_error_handler(void *userData, const xmlError *error) {
    (void)userData;
    if (g_errors_len == g_errors_cap) {
        size_t new_cap = g_errors_cap ? g_errors_cap * 2 : 8;
        g_errors = (lx_error *)realloc(g_errors, new_cap * sizeof(lx_error));
        g_errors_cap = new_cap;
    }
    const char *raw = error->message ? error->message : "";
    size_t len = strlen(raw);
    while (len > 0 && (raw[len - 1] == '\n' || raw[len - 1] == '\r')) len--;
    char *msg = (char *)malloc(len + 1);
    memcpy(msg, raw, len);
    msg[len] = '\0';
    lx_error *e = &g_errors[g_errors_len++];
    e->message = msg;
    e->domain = error->domain;
    e->code = error->code;
    e->line = error->line;
}

LEAN_EXPORT lean_object *lean_xml_global_init(lean_object *w) {
    xmlInitParser();
    // xmlSetStructuredErrorFunc's target is thread-local storage: a handler
    // registered once here, during Lean's `initialize` phase, can be invisible
    // to whichever thread later actually runs a parse. xmlThrDefSetStructuredErrorFunc
    // sets the default every thread starts with instead, which is what a single
    // process-wide handler needs. The per-context alternatives
    // (xmlCtxtSetErrorHandler/xmlXPathSetErrorHandler) would avoid depending on
    // any global state at all, but only exist since libxml2 2.12; this targets
    // the older, more broadly available API (e.g. Ubuntu 24.04 LTS ships 2.9.14).
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    xmlThrDefSetStructuredErrorFunc(NULL, lx_error_handler);
#pragma GCC diagnostic pop
    g_doc_class = lean_register_external_class(lx_doc_finalize, lx_doc_foreach);
    return lean_io_result_mk_ok(lean_box(0));
}

// libxml2 parse options: no network access, no external DTD loading, no
// entity substitution. This library may parse untrusted XML.
static const int LX_PARSE_OPTIONS = XML_PARSE_NONET;

LEAN_EXPORT lean_object *lean_xml_read_memory(b_lean_obj_arg contents, b_lean_obj_arg url, lean_object *w) {
    const char *buf = lean_string_cstr(contents);
    int buf_len = (int)(lean_string_size(contents) - 1);
    const char *u = lean_string_cstr(url);
    const char *u_arg = u[0] != '\0' ? u : NULL;
    xmlDocPtr doc = xmlReadMemory(buf, buf_len, u_arg, NULL, LX_PARSE_OPTIONS);
    lx_doc *h = (lx_doc *)malloc(sizeof(lx_doc));
    h->doc = doc;
    return lean_io_result_mk_ok(lean_alloc_external(g_doc_class, h));
}

LEAN_EXPORT lean_object *lean_xml_read_file(b_lean_obj_arg path, lean_object *w) {
    xmlDocPtr doc = xmlReadFile(lean_string_cstr(path), NULL, LX_PARSE_OPTIONS);
    lx_doc *h = (lx_doc *)malloc(sizeof(lx_doc));
    h->doc = doc;
    return lean_io_result_mk_ok(lean_alloc_external(g_doc_class, h));
}

static lx_doc *lx_get(b_lean_obj_arg h) {
    return (lx_doc *)lean_get_external_data(h);
}

LEAN_EXPORT lean_object *lean_xml_doc_is_null(b_lean_obj_arg h, lean_object *w) {
    return lean_io_result_mk_ok(lean_box(lx_get(h)->doc == NULL ? 1 : 0));
}

LEAN_EXPORT lean_object *lean_xml_doc_root(b_lean_obj_arg h, lean_object *w) {
    xmlDocPtr doc = lx_get(h)->doc;
    xmlNodePtr root = doc ? xmlDocGetRootElement(doc) : NULL;
    return lean_io_result_mk_ok(lean_box_usize((size_t)(uintptr_t)root));
}

LEAN_EXPORT lean_object *lean_xml_doc_dump(b_lean_obj_arg h, lean_object *w) {
    xmlDocPtr doc = lx_get(h)->doc;
    xmlChar *mem = NULL;
    int size = 0;
    if (doc) xmlDocDumpMemory(doc, &mem, &size);
    lean_object *res = lean_mk_string_from_bytes(mem ? (const char *)mem : "", (size_t)size);
    if (mem) xmlFree(mem);
    return lean_io_result_mk_ok(res);
}

LEAN_EXPORT lean_object *lean_xml_node_dump(b_lean_obj_arg h, size_t n, lean_object *w) {
    xmlDocPtr doc = lx_get(h)->doc;
    xmlNodePtr node = (xmlNodePtr)(uintptr_t)n;
    lean_object *res;
    if (doc && node) {
        xmlBufferPtr buf = xmlBufferCreate();
        xmlNodeDump(buf, doc, node, 0, 1);
        res = lean_mk_string_from_bytes((const char *)xmlBufferContent(buf), (size_t)xmlBufferLength(buf));
        xmlBufferFree(buf);
    } else {
        res = lean_mk_string("");
    }
    return lean_io_result_mk_ok(res);
}

LEAN_EXPORT lean_object *lean_xml_node_type(size_t n, lean_object *w) {
    xmlNodePtr node = (xmlNodePtr)(uintptr_t)n;
    return lean_io_result_mk_ok(lean_box_uint32(node ? (uint32_t)node->type : 0));
}

LEAN_EXPORT lean_object *lean_xml_node_name(size_t n, lean_object *w) {
    xmlNodePtr node = (xmlNodePtr)(uintptr_t)n;
    const xmlChar *name = node ? node->name : NULL;
    return lean_io_result_mk_ok(lean_mk_string(name ? (const char *)name : ""));
}

LEAN_EXPORT lean_object *lean_xml_node_content(size_t n, lean_object *w) {
    xmlNodePtr node = (xmlNodePtr)(uintptr_t)n;
    xmlChar *content = node ? xmlNodeGetContent(node) : NULL;
    lean_object *res = lean_mk_string(content ? (const char *)content : "");
    if (content) xmlFree(content);
    return lean_io_result_mk_ok(res);
}

LEAN_EXPORT lean_object *lean_xml_node_first_child(size_t n, lean_object *w) {
    xmlNodePtr node = (xmlNodePtr)(uintptr_t)n;
    xmlNodePtr child = node ? node->children : NULL;
    return lean_io_result_mk_ok(lean_box_usize((size_t)(uintptr_t)child));
}

LEAN_EXPORT lean_object *lean_xml_node_next(size_t n, lean_object *w) {
    xmlNodePtr node = (xmlNodePtr)(uintptr_t)n;
    xmlNodePtr next = node ? node->next : NULL;
    return lean_io_result_mk_ok(lean_box_usize((size_t)(uintptr_t)next));
}

LEAN_EXPORT lean_object *lean_xml_node_prev(size_t n, lean_object *w) {
    xmlNodePtr node = (xmlNodePtr)(uintptr_t)n;
    xmlNodePtr prev = node ? node->prev : NULL;
    return lean_io_result_mk_ok(lean_box_usize((size_t)(uintptr_t)prev));
}

LEAN_EXPORT lean_object *lean_xml_node_parent(size_t n, lean_object *w) {
    xmlNodePtr node = (xmlNodePtr)(uintptr_t)n;
    xmlNodePtr parent = node ? node->parent : NULL;
    return lean_io_result_mk_ok(lean_box_usize((size_t)(uintptr_t)parent));
}

LEAN_EXPORT lean_object *lean_xml_node_ns_href(size_t n, lean_object *w) {
    xmlNodePtr node = (xmlNodePtr)(uintptr_t)n;
    const xmlChar *href = (node && node->ns) ? node->ns->href : NULL;
    return lean_io_result_mk_ok(lean_mk_string(href ? (const char *)href : ""));
}

LEAN_EXPORT lean_object *lean_xml_node_ns_prefix(size_t n, lean_object *w) {
    xmlNodePtr node = (xmlNodePtr)(uintptr_t)n;
    const xmlChar *prefix = (node && node->ns) ? node->ns->prefix : NULL;
    return lean_io_result_mk_ok(lean_mk_string(prefix ? (const char *)prefix : ""));
}

static xmlAttrPtr lx_nth_attr(xmlNodePtr node, uint32_t i) {
    xmlAttrPtr a = node ? node->properties : NULL;
    while (a && i > 0) { a = a->next; i--; }
    return a;
}

LEAN_EXPORT lean_object *lean_xml_node_attr_count(size_t n, lean_object *w) {
    xmlNodePtr node = (xmlNodePtr)(uintptr_t)n;
    uint32_t count = 0;
    for (xmlAttrPtr a = node ? node->properties : NULL; a; a = a->next) count++;
    return lean_io_result_mk_ok(lean_box_uint32(count));
}

LEAN_EXPORT lean_object *lean_xml_node_attr_name(size_t n, uint32_t i, lean_object *w) {
    xmlAttrPtr a = lx_nth_attr((xmlNodePtr)(uintptr_t)n, i);
    return lean_io_result_mk_ok(lean_mk_string(a && a->name ? (const char *)a->name : ""));
}

LEAN_EXPORT lean_object *lean_xml_node_attr_ns_href(size_t n, uint32_t i, lean_object *w) {
    xmlAttrPtr a = lx_nth_attr((xmlNodePtr)(uintptr_t)n, i);
    const xmlChar *href = (a && a->ns) ? a->ns->href : NULL;
    return lean_io_result_mk_ok(lean_mk_string(href ? (const char *)href : ""));
}

LEAN_EXPORT lean_object *lean_xml_node_attr_value(size_t n, uint32_t i, lean_object *w) {
    xmlAttrPtr a = lx_nth_attr((xmlNodePtr)(uintptr_t)n, i);
    xmlChar *val = a ? xmlNodeGetContent((xmlNodePtr)a) : NULL;
    lean_object *res = lean_mk_string(val ? (const char *)val : "");
    if (val) xmlFree(val);
    return lean_io_result_mk_ok(res);
}

LEAN_EXPORT lean_object *lean_xml_has_prop(size_t n, b_lean_obj_arg name, lean_object *w) {
    xmlNodePtr node = (xmlNodePtr)(uintptr_t)n;
    xmlAttrPtr a = node ? xmlHasProp(node, (const xmlChar *)lean_string_cstr(name)) : NULL;
    return lean_io_result_mk_ok(lean_box(a ? 1 : 0));
}

LEAN_EXPORT lean_object *lean_xml_get_prop(size_t n, b_lean_obj_arg name, lean_object *w) {
    xmlNodePtr node = (xmlNodePtr)(uintptr_t)n;
    xmlChar *val = node ? xmlGetProp(node, (const xmlChar *)lean_string_cstr(name)) : NULL;
    lean_object *res = lean_mk_string(val ? (const char *)val : "");
    if (val) xmlFree(val);
    return lean_io_result_mk_ok(res);
}

LEAN_EXPORT lean_object *lean_xml_has_ns_prop(size_t n, b_lean_obj_arg name, b_lean_obj_arg nsHref, lean_object *w) {
    xmlNodePtr node = (xmlNodePtr)(uintptr_t)n;
    const char *ns = lean_string_cstr(nsHref);
    xmlAttrPtr a = node
        ? xmlHasNsProp(node, (const xmlChar *)lean_string_cstr(name), ns[0] ? (const xmlChar *)ns : NULL)
        : NULL;
    return lean_io_result_mk_ok(lean_box(a ? 1 : 0));
}

LEAN_EXPORT lean_object *lean_xml_get_ns_prop(size_t n, b_lean_obj_arg name, b_lean_obj_arg nsHref, lean_object *w) {
    xmlNodePtr node = (xmlNodePtr)(uintptr_t)n;
    const char *ns = lean_string_cstr(nsHref);
    xmlChar *val = node
        ? xmlGetNsProp(node, (const xmlChar *)lean_string_cstr(name), ns[0] ? (const xmlChar *)ns : NULL)
        : NULL;
    lean_object *res = lean_mk_string(val ? (const char *)val : "");
    if (val) xmlFree(val);
    return lean_io_result_mk_ok(res);
}

LEAN_EXPORT lean_object *lean_xml_search_ns(b_lean_obj_arg h, size_t n, b_lean_obj_arg prefix, lean_object *w) {
    xmlDocPtr doc = lx_get(h)->doc;
    xmlNodePtr node = (xmlNodePtr)(uintptr_t)n;
    const char *p = lean_string_cstr(prefix);
    const xmlChar *p_arg = p[0] != '\0' ? (const xmlChar *)p : NULL;
    xmlNsPtr ns = (doc && node) ? xmlSearchNs(doc, node, p_arg) : NULL;
    return lean_io_result_mk_ok(lean_mk_string(ns && ns->href ? (const char *)ns->href : ""));
}

LEAN_EXPORT lean_object *lean_xml_error_count(lean_object *w) {
    return lean_io_result_mk_ok(lean_box_uint32((uint32_t)g_errors_len));
}

LEAN_EXPORT lean_object *lean_xml_error_message(uint32_t i, lean_object *w) {
    const char *msg = i < g_errors_len ? g_errors[i].message : "";
    return lean_io_result_mk_ok(lean_mk_string(msg));
}

LEAN_EXPORT lean_object *lean_xml_error_domain(uint32_t i, lean_object *w) {
    uint32_t v = i < g_errors_len ? (uint32_t)g_errors[i].domain : 0;
    return lean_io_result_mk_ok(lean_box_uint32(v));
}

LEAN_EXPORT lean_object *lean_xml_error_code(uint32_t i, lean_object *w) {
    uint32_t v = i < g_errors_len ? (uint32_t)g_errors[i].code : 0;
    return lean_io_result_mk_ok(lean_box_uint32(v));
}

LEAN_EXPORT lean_object *lean_xml_error_line(uint32_t i, lean_object *w) {
    uint32_t v = i < g_errors_len ? (uint32_t)g_errors[i].line : 0;
    return lean_io_result_mk_ok(lean_box_uint32(v));
}

LEAN_EXPORT lean_object *lean_xml_clear_errors(lean_object *w) {
    for (size_t i = 0; i < g_errors_len; i++) free(g_errors[i].message);
    g_errors_len = 0;
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_object *lean_xml_xpath_new_context(b_lean_obj_arg h, lean_object *w) {
    xmlDocPtr doc = lx_get(h)->doc;
    xmlXPathContextPtr ctx = doc ? xmlXPathNewContext(doc) : NULL;
    return lean_io_result_mk_ok(lean_box_usize((size_t)(uintptr_t)ctx));
}

LEAN_EXPORT lean_object *lean_xml_xpath_free_context(size_t ctx, lean_object *w) {
    if (ctx) xmlXPathFreeContext((xmlXPathContextPtr)(uintptr_t)ctx);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_object *lean_xml_xpath_register_ns(size_t ctx, b_lean_obj_arg prefix, b_lean_obj_arg href, lean_object *w) {
    int rc = xmlXPathRegisterNs(
        (xmlXPathContextPtr)(uintptr_t)ctx,
        (const xmlChar *)lean_string_cstr(prefix),
        (const xmlChar *)lean_string_cstr(href));
    return lean_io_result_mk_ok(lean_box(rc == 0 ? 1 : 0));
}

LEAN_EXPORT lean_object *lean_xml_xpath_eval(size_t ctx, b_lean_obj_arg expr, lean_object *w) {
    xmlXPathObjectPtr obj = xmlXPathEvalExpression(
        (const xmlChar *)lean_string_cstr(expr), (xmlXPathContextPtr)(uintptr_t)ctx);
    return lean_io_result_mk_ok(lean_box_usize((size_t)(uintptr_t)obj));
}

LEAN_EXPORT lean_object *lean_xml_xpath_free_object(size_t obj, lean_object *w) {
    if (obj) xmlXPathFreeObject((xmlXPathObjectPtr)(uintptr_t)obj);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_object *lean_xml_xpath_is_nodeset(size_t obj, lean_object *w) {
    xmlXPathObjectPtr o = (xmlXPathObjectPtr)(uintptr_t)obj;
    return lean_io_result_mk_ok(lean_box((o && o->type == XPATH_NODESET) ? 1 : 0));
}

LEAN_EXPORT lean_object *lean_xml_xpath_node_count(size_t obj, lean_object *w) {
    xmlXPathObjectPtr o = (xmlXPathObjectPtr)(uintptr_t)obj;
    uint32_t n = (o && o->nodesetval) ? (uint32_t)o->nodesetval->nodeNr : 0;
    return lean_io_result_mk_ok(lean_box_uint32(n));
}

LEAN_EXPORT lean_object *lean_xml_xpath_node_at(size_t obj, uint32_t i, lean_object *w) {
    xmlXPathObjectPtr o = (xmlXPathObjectPtr)(uintptr_t)obj;
    xmlNodePtr node = NULL;
    if (o && o->nodesetval && i < (uint32_t)o->nodesetval->nodeNr) node = o->nodesetval->nodeTab[i];
    return lean_io_result_mk_ok(lean_box_usize((size_t)(uintptr_t)node));
}
