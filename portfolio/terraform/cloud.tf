terraform { 
    cloud { 
        organization = "mahwill29" 
        workspaces { 
            name = "example-workspace" 
        } 
    }
}