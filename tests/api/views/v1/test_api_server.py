# -*- coding: utf-8 -*-
"""Tests for /v1/server API endpoint."""


import copy
import random
import uuid

import pytest

from cephlcm.common.models import server
from cephlcm.common.models import task
from cephlcm.common.models import user


@pytest.fixture(scope="module")
def normal_user(sudo_user):
    return user.UserModel.make_user(
        str(uuid.uuid4()), "qwerty",
        "{0}@example.com".format(uuid.uuid4()),
        str(uuid.uuid4()), [],
        initiator_id=sudo_user.model_id
    )


@pytest.fixture
def mongo_collection(pymongo_connection):
    return pymongo_connection.db.server


@pytest.fixture
def clean_server_collection(pymongo_connection):
    pymongo_connection.db.server.remove({})


def random_ip():
    ints = [random.randint(1, 255) for _ in range(4)]
    ints = map(str, ints)
    ints = ".".join(ints)

    return ints


def create_server():
    name = str(uuid.uuid4())
    username = str(uuid.uuid4())
    fqdn = str(uuid.uuid4())
    ip = random_ip()

    return server.ServerModel.create(name, username, fqdn, ip)


def test_api_get_access(sudo_client_v1, client_v1, sudo_user, freeze_time,
                        normal_user):
    response = client_v1.get("/v1/server/")
    assert response.status_code == 401
    assert response.json["error"] == "Unauthorized"

    client_v1.login(normal_user.login, "qwerty")
    response = client_v1.get("/v1/server/")
    assert response.status_code == 403
    assert response.json["error"] == "Forbidden"

    response = sudo_client_v1.get("/v1/server/")
    assert response.status_code == 200


def test_get_server(sudo_client_v1, clean_server_collection, freeze_time):
    srv = create_server()
    freeze_time.return_value += 1
    srv.save()

    response = sudo_client_v1.get("/v1/server/")
    assert response.status_code == 200
    assert response.json["total"] == 1
    assert len(response.json["items"]) == 1

    response_model = response.json["items"][0]
    assert response_model["model"] == server.ServerModel.MODEL_NAME
    assert response_model["id"] == srv.model_id
    assert response_model["time_updated"] == int(freeze_time.return_value)
    assert response_model["time_deleted"] == 0
    assert response_model["version"] == 2

    response = sudo_client_v1.get(
        "/v1/server/{0}/".format(response_model["id"])
    )
    assert response.status_code == 200
    assert response.json == response_model

    response = sudo_client_v1.get(
        "/v1/server/{0}/version/".format(response_model["id"])
    )
    assert response.status_code == 200
    assert response.json["total"] == 2
    assert len(response.json["items"]) == 2
    # sorted by version
    assert response.json["items"][0] == response_model

    response = sudo_client_v1.get(
        "/v1/server/{0}/version/2/".format(response_model["id"])
    )
    assert response.status_code == 200
    assert response.json == response_model

    response = sudo_client_v1.get(
        "/v1/server/{0}/version/20/".format(response_model["id"])
    )
    assert response.status_code == 404


@pytest.mark.parametrize("host", ("localhost", "127.0.0.1"))
def test_post_server(host, client_v1, normal_user, sudo_client_v1,
                     freeze_time, clean_server_collection, pymongo_connection):
    request = {
        "host": host,
        "username": str(uuid.uuid4())
    }
    response = client_v1.post("/v1/server/", data=request)
    assert response.status_code == 401

    client_v1.login(normal_user.login, "qwerty")
    response = client_v1.post("/v1/server/", data=request)
    assert response.status_code == 403

    response = sudo_client_v1.post("/v1/server/", data=request)
    assert response.status_code == 200
    assert response.json == {}

    found_task = pymongo_connection.db.task.find_one({"data.host": host})
    assert found_task

    assert found_task["task_type"] == task.Task.TASK_TYPE_SERVER_DISCOVERY
    assert found_task["time"]["created"] == int(freeze_time.return_value)
    assert found_task["data"]["host"] == host
    assert found_task["data"]["username"] == request["username"]

    servers = pymongo_connection.db.server.find({})
    assert servers.count() == 0


def test_update_server(sudo_client_v1, client_v1, normal_user):
    srv = create_server()

    response = sudo_client_v1.get("/v1/server/{0}/".format(srv.model_id))
    assert response.status_code == 200

    api_model = response.json
    old_model = copy.deepcopy(api_model)

    for key in api_model["data"]:
        api_model["data"][key] = str(uuid.uuid4())
    api_model["data"]["ip"] = random_ip()
    api_model["data"]["facts"] = {str(uuid.uuid4()): str(uuid.uuid4())}
    api_model["data"]["state"] = server.ServerModel.STATE_MAINTENANCE_RECONFIG

    response = client_v1.put("/v1/server/{0}/".format(srv.model_id),
                             data=api_model)
    assert response.status_code == 401

    client_v1.login(normal_user.login, "qwerty")
    response = client_v1.put("/v1/server/{0}/".format(srv.model_id),
                             data=api_model)
    assert response.status_code == 403

    response = sudo_client_v1.put("/v1/server/{0}/".format(srv.model_id),
                                  data=api_model)
    assert response.status_code == 200
    assert response.json["data"]["ip"] == api_model["data"]["ip"]
    assert response.json["data"]["name"] == api_model["data"]["name"]
    assert response.json["data"]["fqdn"] == api_model["data"]["fqdn"]
    assert response.json["data"]["state"] == old_model["data"]["state"]
    assert response.json["data"]["facts"] == old_model["data"]["facts"]
    assert response.json["data"]["cluster_id"] == \
        old_model["data"]["cluster_id"]


def test_delete_server(sudo_client_v1, client_v1, normal_user, freeze_time):
    srv = create_server()

    response = client_v1.delete("/v1/server/{0}/".format(srv.model_id))
    assert response.status_code == 401

    client_v1.login(normal_user.login, "qwerty")
    response = client_v1.delete("/v1/server/{0}/".format(srv.model_id))
    assert response.status_code == 403

    response = sudo_client_v1.delete("/v1/server/{0}/".format(srv.model_id))
    assert response.status_code == 200
    assert response.json["time_deleted"] == int(freeze_time.return_value)


def test_delete_deleted_server(sudo_client_v1):
    srv = create_server()
    srv.delete()

    response = sudo_client_v1.delete("/v1/server/{0}/".format(srv.model_id))
    assert response.status_code == 400


def test_list_deleted_server(sudo_client_v1, clean_server_collection):
    srv = create_server()
    srv.delete()

    response = sudo_client_v1.get("/v1/server/")
    assert response.status_code == 200
    assert response.json["items"] == []
    assert response.json["total"] == 0

    response = sudo_client_v1.get("/v1/server/{0}/".format(srv.model_id))
    assert response.status_code == 200
    assert response.json["version"] == 2