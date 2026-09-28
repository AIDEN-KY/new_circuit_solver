from app.models import SpiceNetlist
from app.spice_validator import validate_spice_netlist


def test_spice_netlist_requires_end_and_nodes() -> None:
    result = validate_spice_netlist(
        SpiceNetlist(raw="V1 in 0 DC 12\nR1 in out 10\n.op\n.end")
    )
    assert result.validation_passed is True
    assert result.elements == ["V1 in 0 DC 12", "R1 in out 10"]


def test_spice_netlist_rejects_duplicate_element() -> None:
    result = validate_spice_netlist(
        SpiceNetlist(raw="R1 in 0 10\nR1 in 0 20\n.end")
    )
    assert result.validation_passed is False
    assert any("重复" in message for message in result.validation_messages)
