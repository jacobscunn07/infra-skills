import json
import subprocess


def check_tool(cmd, parse=None):
    """Run cmd and return the version string, or None if not installed."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        output = (r.stdout or r.stderr).strip()
        if r.returncode != 0 or not output:
            return None
        return parse(output) if parse else output.split("\n")[0]
    except FileNotFoundError:
        return None
    except Exception:
        return None


def terraform_version():
    v = check_tool(
        ["terraform", "version", "-json"],
        parse=lambda out: json.loads(out).get("terraform_version")
    )
    if v:
        return v
    return check_tool(
        ["terraform", "version"],
        parse=lambda out: out.split("\n")[0].removeprefix("Terraform v").strip()
    )


def kubectl_version():
    v = check_tool(
        ["kubectl", "version", "--client", "-o", "json"],
        parse=lambda out: json.loads(out).get("clientVersion", {}).get("gitVersion")
    )
    if v:
        return v
    return check_tool(
        ["kubectl", "version", "--client"],
        parse=lambda out: out.split("\n")[0].split(": ")[-1].strip()
    )


tools = {
    "terraform":      terraform_version(),
    "aws":            check_tool(["aws", "--version"]),
    "gh":             check_tool(["gh", "--version"],
                          parse=lambda out: out.split("\n")[0].removeprefix("gh version").strip()),
    "git":            check_tool(["git", "--version"],
                          parse=lambda out: out.removeprefix("git version ").strip()),
    "docker":         check_tool(["docker", "--version"],
                          parse=lambda out: out.removeprefix("Docker version ").split(",")[0].strip()),
    "kubectl":        kubectl_version(),
    "jq":             check_tool(["jq", "--version"]),
    "tflint":         check_tool(["tflint", "--version"],
                          parse=lambda out: out.split("\n")[0].removeprefix("TFLint version ").strip()),
    "terraform-docs": check_tool(["terraform-docs", "--version"],
                          parse=lambda out: out.removeprefix("terraform-docs version ").split()[0].strip()),
    "trivy":          check_tool(["trivy", "--version"],
                          parse=lambda out: out.split("\n")[0].removeprefix("Version: ").strip()),
    "yq":             check_tool(["yq", "--version"],
                          parse=lambda out: out.split("version ")[-1].strip()),
}

lines = [
    f"  {name}: {version if version else 'not installed'}"
    for name, version in tools.items()
]

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": "Installed CLI tool versions:\n" + "\n".join(lines)
    }
}))
