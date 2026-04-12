"use strict";
"require form";
"require baseclass";
"require uci";
"require view.podkop_plus.main as main";

const UCI_PACKAGE = main.PODKOP_UCI_PACKAGE;

function createRulesetContent(section) {
  let o = section.option(form.Flag, "enabled", _("Enable"));
  o.default = "1";
  o.rmempty = false;
  o.editable = true;

  o = section.option(form.ListValue, "type", _("Type"));
  o.value("local", _("Local"));
  o.value("remote", _("Remote"));
  o.default = "remote";
  o.rmempty = false;
  o.editable = true;

  o = section.option(form.ListValue, "format", _("Format"));
  o.value("binary", _("Binary file"));
  o.value("source", _("Source file"));
  o.default = "binary";
  o.rmempty = false;
  o.editable = true;

  o = section.option(
    form.Value,
    "path",
    _("Path"),
    _("Local file path to a sing-box rule set"),
  );
  o.datatype = "file";
  o.placeholder = "/etc/podkop/ruleset/example.srs";
  o.rmempty = false;
  o.depends("type", "local");
  o.modalonly = true;
  o.validate = function (_section_id, value) {
    const validation = main.validatePath(value);
    return validation.valid ? true : validation.message;
  };

  o = section.option(
    form.Value,
    "url",
    _("Rule set URL"),
    _("Remote URL to a sing-box rule set"),
  );
  o.placeholder = "https://example.com/ruleset.srs";
  o.rmempty = false;
  o.depends("type", "remote");
  o.modalonly = true;
  o.validate = function (_section_id, value) {
    const validation = main.validateUrl(value);
    return validation.valid ? true : validation.message;
  };

  o = section.option(
    form.ListValue,
    "outbound",
    _("Download Node"),
    _("Optional node used to download this remote rule set"),
  );
  o.value("", _("Direct"));
  o.depends("type", "remote");
  o.modalonly = true;
  o.load = function (section_id) {
    delete this.keylist;
    delete this.vallist;

    this.value("", _("Direct"));
    uci.sections(UCI_PACKAGE, "node", (node) => {
      if (node[".name"] !== section_id && node.enabled !== "0") {
        this.value(node[".name"], node[".name"]);
      }
    });

    return this.super("load", section_id);
  };

  o = section.option(
    form.Value,
    "update_interval",
    _("Update interval"),
    _("How often this remote rule set should be refreshed"),
  );
  o.placeholder = "1d";
  o.depends("type", "remote");
  o.modalonly = true;
}

const EntryPoint = {
  createRulesetContent,
};

return baseclass.extend(EntryPoint);
