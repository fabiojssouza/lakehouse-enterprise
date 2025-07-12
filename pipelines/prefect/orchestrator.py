"""
Orquestrador Prefect para Modern Data Stack
Lakehouse Enterprise - Versão 2.1

RESPONSABILIDADE: Apenas orquestração de componentes
- Airbyte: Ingestão de dados (APIs → Bronze)
- DBT: Transformações (Bronze → Staging → Silver → Gold)

NÃO faz ingestão direta de dados!
"""

import os
import time
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional

from prefect import flow, task, get_run_logger
from prefect.blocks.system import Secret
from prefect.task_runners import SequentialTaskRunner
from prefect_airbyte import AirbyteConnection
from prefect_dbt import DbtCoreOperation, DbtCloudJob

import requests
import json


# Configurações
AIRBYTE_SERVER_HOST = "airbyte-server.airbyte.svc.cluster.local"
AIRBYTE_SERVER_PORT = 8001
AIRBYTE_API_URL = f"http://{AIRBYTE_SERVER_HOST}:{AIRBYTE_SERVER_PORT}/api/v1"

DBT_PROJECT_DIR = "/opt/prefect/dbt"
DBT_PROFILES_DIR = "/opt/prefect/dbt"

# IDs das conexões Airbyte (configurados via UI)
FACEBOOK_ADS_CONNECTION_ID = "facebook-ads-connection"
GOOGLE_ADS_CONNECTION_ID = "google-ads-connection"
ACTIVECAMPAIGN_CONNECTION_ID = "activecampaign-connection"


@task
def check_airbyte_health() -> bool:
    """Verifica se o Airbyte está saudável"""
    logger = get_run_logger()
    logger.info("Verificando saúde do Airbyte")
    
    try:
        response = requests.get(f"{AIRBYTE_API_URL}/health", timeout=30)
        response.raise_for_status()
        
        health_data = response.json()
        is_healthy = health_data.get("available", False)
        
        if is_healthy:
            logger.info("Airbyte está saudável")
        else:
            logger.warning("Airbyte não está saudável")
            
        return is_healthy
        
    except Exception as e:
        logger.error(f"Erro ao verificar saúde do Airbyte: {str(e)}")
        return False


@task
def trigger_airbyte_sync(connection_id: str, connection_name: str) -> Dict[str, Any]:
    """Dispara sincronização no Airbyte"""
    logger = get_run_logger()
    logger.info(f"Disparando sincronização Airbyte: {connection_name}")
    
    try:
        # Usar bloco Airbyte do Prefect
        airbyte_connection = AirbyteConnection.load(connection_id)
        
        # Disparar sincronização
        sync_result = airbyte_connection.trigger_sync()
        
        logger.info(f"Sincronização {connection_name} iniciada: {sync_result.job_id}")
        
        return {
            "connection_id": connection_id,
            "connection_name": connection_name,
            "job_id": sync_result.job_id,
            "status": "started",
            "started_at": datetime.now().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Erro ao disparar sincronização {connection_name}: {str(e)}")
        raise


@task
def wait_for_airbyte_sync(job_info: Dict[str, Any], timeout_minutes: int = 30) -> Dict[str, Any]:
    """Aguarda conclusão da sincronização Airbyte"""
    logger = get_run_logger()
    connection_name = job_info["connection_name"]
    job_id = job_info["job_id"]
    
    logger.info(f"Aguardando conclusão da sincronização {connection_name} (Job: {job_id})")
    
    start_time = time.time()
    timeout_seconds = timeout_minutes * 60
    
    try:
        airbyte_connection = AirbyteConnection.load(job_info["connection_id"])
        
        while True:
            # Verificar status do job
            job_status = airbyte_connection.get_job_status(job_id)
            
            logger.info(f"Status da sincronização {connection_name}: {job_status}")
            
            if job_status in ["succeeded", "completed"]:
                logger.info(f"Sincronização {connection_name} concluída com sucesso")
                return {
                    **job_info,
                    "status": "completed",
                    "completed_at": datetime.now().isoformat()
                }
            elif job_status in ["failed", "cancelled"]:
                logger.error(f"Sincronização {connection_name} falhou: {job_status}")
                raise Exception(f"Sincronização {connection_name} falhou com status: {job_status}")
            
            # Verificar timeout
            if time.time() - start_time > timeout_seconds:
                logger.error(f"Timeout na sincronização {connection_name}")
                raise Exception(f"Timeout aguardando sincronização {connection_name}")
            
            # Aguardar antes da próxima verificação
            time.sleep(30)
            
    except Exception as e:
        logger.error(f"Erro aguardando sincronização {connection_name}: {str(e)}")
        raise


@task
def run_dbt_command(command: str, project_dir: str = DBT_PROJECT_DIR) -> Dict[str, Any]:
    """Executa comando DBT"""
    logger = get_run_logger()
    logger.info(f"Executando comando DBT: {command}")
    
    try:
        dbt_operation = DbtCoreOperation(
            commands=[command],
            project_dir=project_dir,
            profiles_dir=DBT_PROFILES_DIR
        )
        
        result = dbt_operation.run()
        
        logger.info(f"Comando DBT '{command}' executado com sucesso")
        
        return {
            "command": command,
            "status": "success",
            "result": str(result),
            "executed_at": datetime.now().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Erro executando comando DBT '{command}': {str(e)}")
        raise


@task
def run_dbt_pipeline() -> List[Dict[str, Any]]:
    """Executa pipeline completo do DBT"""
    logger = get_run_logger()
    logger.info("Iniciando pipeline DBT completo")
    
    # Comandos DBT em ordem
    dbt_commands = [
        "dbt deps",           # Instalar dependências
        "dbt seed",           # Carregar seeds
        "dbt run --models staging",     # Executar modelos staging
        "dbt run --models silver",      # Executar modelos silver (Data Vault)
        "dbt run --models gold",        # Executar modelos gold (Marts)
        "dbt test",           # Executar testes
        "dbt docs generate"   # Gerar documentação
    ]
    
    results = []
    
    for command in dbt_commands:
        try:
            result = run_dbt_command(command)
            results.append(result)
            logger.info(f"✅ {command} - Sucesso")
        except Exception as e:
            logger.error(f"❌ {command} - Falhou: {str(e)}")
            # Para comandos críticos, interromper pipeline
            if command in ["dbt run --models staging", "dbt run --models silver"]:
                raise
            # Para comandos não críticos, continuar
            results.append({
                "command": command,
                "status": "failed",
                "error": str(e),
                "executed_at": datetime.now().isoformat()
            })
    
    logger.info("Pipeline DBT concluído")
    return results


@task
def send_notification(message: str, status: str = "info"):
    """Envia notificação sobre status do pipeline"""
    logger = get_run_logger()
    logger.info(f"Notificação [{status}]: {message}")
    
    # Aqui você pode integrar com Slack, Teams, email, etc.
    # Por enquanto, apenas log
    
    notification_data = {
        "message": message,
        "status": status,
        "timestamp": datetime.now().isoformat(),
        "pipeline": "lakehouse-etl"
    }
    
    # Exemplo de integração com webhook (descomente se necessário)
    # webhook_url = os.getenv("NOTIFICATION_WEBHOOK_URL")
    # if webhook_url:
    #     requests.post(webhook_url, json=notification_data)
    
    return notification_data


@flow(
    name="Airbyte Ingestion Orchestrator",
    description="Orquestra ingestão de dados via Airbyte"
)
def airbyte_ingestion_flow(connections: List[str] = None) -> List[Dict[str, Any]]:
    """Flow para orquestrar ingestão via Airbyte"""
    logger = get_run_logger()
    logger.info("Iniciando orquestração de ingestão Airbyte")
    
    # Conexões padrão se não especificadas
    if connections is None:
        connections = [
            FACEBOOK_ADS_CONNECTION_ID,
            GOOGLE_ADS_CONNECTION_ID,
            ACTIVECAMPAIGN_CONNECTION_ID
        ]
    
    # Verificar saúde do Airbyte
    is_healthy = check_airbyte_health()
    if not is_healthy:
        raise Exception("Airbyte não está saudável - abortando pipeline")
    
    # Disparar sincronizações
    sync_jobs = []
    for connection_id in connections:
        try:
            job_info = trigger_airbyte_sync(connection_id, connection_id)
            sync_jobs.append(job_info)
        except Exception as e:
            logger.error(f"Falha ao disparar sincronização {connection_id}: {str(e)}")
            # Continuar com outras conexões
            continue
    
    # Aguardar conclusão de todas as sincronizações
    completed_jobs = []
    for job_info in sync_jobs:
        try:
            completed_job = wait_for_airbyte_sync(job_info)
            completed_jobs.append(completed_job)
        except Exception as e:
            logger.error(f"Falha na sincronização {job_info['connection_name']}: {str(e)}")
            # Continuar com outras sincronizações
            continue
    
    logger.info(f"Ingestão Airbyte concluída: {len(completed_jobs)} sincronizações bem-sucedidas")
    return completed_jobs


@flow(
    name="DBT Transformation Orchestrator", 
    description="Orquestra transformações via DBT"
)
def dbt_transformation_flow() -> List[Dict[str, Any]]:
    """Flow para orquestrar transformações DBT"""
    logger = get_run_logger()
    logger.info("Iniciando orquestração de transformações DBT")
    
    try:
        # Executar pipeline DBT
        dbt_results = run_dbt_pipeline()
        
        # Verificar se houve falhas críticas
        failed_critical = [r for r in dbt_results if r["status"] == "failed" and 
                          any(cmd in r["command"] for cmd in ["staging", "silver"])]
        
        if failed_critical:
            raise Exception(f"Falhas críticas no DBT: {failed_critical}")
        
        logger.info("Transformações DBT concluídas com sucesso")
        return dbt_results
        
    except Exception as e:
        logger.error(f"Erro nas transformações DBT: {str(e)}")
        raise


@flow(
    name="Daily ETL Orchestrator",
    description="Orquestrador principal do pipeline ETL diário",
    task_runner=SequentialTaskRunner()
)
def daily_etl_orchestrator(
    run_ingestion: bool = True,
    run_transformations: bool = True,
    connections: List[str] = None
):
    """Flow principal que orquestra todo o pipeline ETL"""
    logger = get_run_logger()
    logger.info("🚀 Iniciando pipeline ETL diário")
    
    pipeline_start = datetime.now()
    
    try:
        # Notificação de início
        send_notification("Pipeline ETL diário iniciado", "info")
        
        ingestion_results = []
        transformation_results = []
        
        # Fase 1: Ingestão via Airbyte
        if run_ingestion:
            logger.info("📥 Fase 1: Ingestão de dados via Airbyte")
            ingestion_results = airbyte_ingestion_flow(connections)
            
            if not ingestion_results:
                logger.warning("Nenhuma ingestão bem-sucedida - continuando com transformações")
            else:
                logger.info(f"✅ Ingestão concluída: {len(ingestion_results)} fontes")
        
        # Fase 2: Transformações via DBT
        if run_transformations:
            logger.info("🔄 Fase 2: Transformações via DBT")
            transformation_results = dbt_transformation_flow()
            logger.info("✅ Transformações concluídas")
        
        # Pipeline concluído com sucesso
        pipeline_end = datetime.now()
        duration = pipeline_end - pipeline_start
        
        success_message = f"""
        ✅ Pipeline ETL concluído com sucesso!
        
        📊 Resumo:
        - Duração: {duration}
        - Ingestões: {len(ingestion_results)}
        - Transformações DBT: {len(transformation_results)}
        - Início: {pipeline_start.strftime('%Y-%m-%d %H:%M:%S')}
        - Fim: {pipeline_end.strftime('%Y-%m-%d %H:%M:%S')}
        """
        
        send_notification(success_message, "success")
        logger.info(success_message)
        
        return {
            "status": "success",
            "duration": str(duration),
            "ingestion_results": ingestion_results,
            "transformation_results": transformation_results,
            "started_at": pipeline_start.isoformat(),
            "completed_at": pipeline_end.isoformat()
        }
        
    except Exception as e:
        # Pipeline falhou
        pipeline_end = datetime.now()
        duration = pipeline_end - pipeline_start
        
        error_message = f"""
        ❌ Pipeline ETL falhou!
        
        🚨 Erro: {str(e)}
        - Duração até falha: {duration}
        - Início: {pipeline_start.strftime('%Y-%m-%d %H:%M:%S')}
        - Falha: {pipeline_end.strftime('%Y-%m-%d %H:%M:%S')}
        """
        
        send_notification(error_message, "error")
        logger.error(error_message)
        
        raise


@flow(
    name="Hourly Incremental Sync",
    description="Sincronização incremental a cada hora"
)
def hourly_incremental_sync():
    """Flow para sincronização incremental horária"""
    logger = get_run_logger()
    logger.info("🔄 Iniciando sincronização incremental horária")
    
    # Apenas ingestão incremental, sem transformações completas
    ingestion_results = airbyte_ingestion_flow()
    
    # Executar apenas modelos incrementais do DBT
    incremental_commands = [
        "dbt run --models staging --select state:modified+",
        "dbt run --models silver --select state:modified+",
        "dbt run --models gold --select state:modified+"
    ]
    
    for command in incremental_commands:
        try:
            run_dbt_command(command)
        except Exception as e:
            logger.warning(f"Comando incremental falhou: {command} - {str(e)}")
            # Continuar com próximo comando
            continue
    
    logger.info("✅ Sincronização incremental concluída")


if __name__ == "__main__":
    # Para execução local/teste
    daily_etl_orchestrator()

