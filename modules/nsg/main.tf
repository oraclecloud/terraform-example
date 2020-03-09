data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "nsg" {
  name = var.resource_group
}

locals {
  location = var.location != "" ? var.location : data.azurerm_resource_group.nsg.location

  tags = merge(data.azurerm_resource_group.nsg.tags, var.tags)

  // Is there a way to derive this safely? Add in PaaS services?
  service_tags = [
    "VirtualNetwork",
    "AzureLoadBalancer",
    "Internet"
  ]

  asg_id = {
    for asg in var.asgs :
    asg => azurerm_application_security_group.asg[asg].id
  }

  nsg_rules = flatten([
    for nsg in var.nsgs : [
      for rule in nsg.rules : {
        nsg      = nsg.name
        priority = rule.priority
        name     = rule.name
        source   = rule.source
        dest     = rule.dest
        ports    = rule.ports
      }
    ]
  ])
}

resource "azurerm_application_security_group" "asg" {
  resource_group_name = data.azurerm_resource_group.nsg.name
  location            = local.location
  tags                = local.tags

  for_each = toset(var.asgs)
  name     = each.value

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_network_security_group" "nsg" {
  resource_group_name = data.azurerm_resource_group.nsg.name
  location            = local.location
  tags                = local.tags

  for_each = toset(var.nsgs[*].name)
  name     = each.value

  lifecycle {
    ignore_changes = [tags]
  }
}


resource "azurerm_network_security_rule" "rule" {
  resource_group_name = data.azurerm_resource_group.nsg.name

  for_each = {
    for rule in local.nsg_rules :
    "${rule.nsg}-${rule.priority}" => rule
  }

  network_security_group_name                = azurerm_network_security_group.nsg[each.value.nsg].name
  priority                                   = each.value.priority
  name                                       = each.value.name
  direction                                  = "Inbound"
  access                                     = "Allow"
  source_address_prefix                      = contains(var.asgs, each.value.source) ? null : each.value.source
  source_application_security_group_ids      = contains(var.asgs, each.value.source) ? [azurerm_application_security_group.asg[each.value.source].id] : null
  source_port_range                          = "*"
  destination_address_prefix                 = contains(var.asgs, each.value.dest) ? null : each.value.dest
  destination_application_security_group_ids = contains(var.asgs, each.value.dest) ? [azurerm_application_security_group.asg[each.value.dest].id] : null
  destination_port_ranges                    = each.value.ports
  protocol                                   = "Tcp"
}
